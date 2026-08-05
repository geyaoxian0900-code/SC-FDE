#include "gd32e50x.h"
#include "systick.h"
#include <stdio.h>
#include <string.h>

/* 整体结构：这份代码把一个 8 位数据拆成 8 个 bit。
	 每个 bit 再用长度为 31 的 PN 码扩频，所以 1 个 bit 会变成 31 个 chip。
   真正发送的帧不是只有数据，还在前面加了 4 位前导码 1010，用于接收端做同步。
   所以整帧长度是：PREAMBLE_LEN + PAYLOAD_BITS = 4 + 8 = 12 个 bit。
   每 bit 31 个 chip，所以总长度是 16 * 31 = 496 chip*/
	 
	 
#define PN_CODE_LEN      31    // 定义PN码长度31
#define TEST_ROUNDS 200				//总共测试 200 轮。
#define PAYLOAD_BITS 8				//有效数据长度 8 bit，也就是 1 字节。
#define PREAMBLE_LEN 8				//前导码长度 8 bit。
#define FRAME_BITS (PREAMBLE_LEN + PAYLOAD_BITS)		//整帧一共 16 bit。



uint8_t PN_Code[PN_CODE_LEN];		// 保存 PN 序列本身，元素是 0/1
int8_t  PN_BPSK[PN_CODE_LEN];		//保存 PN 序列映射成 BPSK 后的形式，元素是 +1/-1，方便做相关运算。
static uint32_t rng_state = 1;	//伪随机数种子，用来模拟噪声。

const uint8_t PREAMBLE_BITS[PREAMBLE_LEN] = {1, 0, 1, 0, 1, 0, 1, 0}; //固定前导码，用于同步定位。
static uint8_t tx_stream[FRAME_BITS * PN_CODE_LEN];
static uint8_t rx_stream[FRAME_BITS * PN_CODE_LEN + PN_CODE_LEN];
static uint8_t *tx_active_stream = NULL;									//当前“发送流”的指针。
static uint16_t tx_chip_index = 0;												//当前已经发送到第几个 chip。
static uint16_t tx_chip_length = 0;												//当前发送流总长度。
typedef struct
{
    uint16_t ok_count;
    uint16_t sync_ok_count;
    uint16_t data_ok_when_sync_ok;
    uint16_t last_best_offset;
} test_result_t;

typedef enum
{
    RX_MODE_SIMULATION = 0,
    RX_MODE_REAL = 1
} rx_mode_t;

static rx_mode_t g_rx_mode = RX_MODE_SIMULATION;

#define APP_MODE_TEST 0
#define APP_MODE_WORK 1

static uint8_t g_app_mode = APP_MODE_WORK;


//==================== 把 printf 重定向到串口 ====================
int fputc(int ch, FILE *f)
{
    usart_data_transmit(USART0, (uint8_t)ch);
    while(usart_flag_get(USART0, USART_FLAG_TC) == RESET);
    return ch;
}

//==================== 系统初始化占位函数 ====================
void system_init(void)
{
    // 空
}

//==================== USART0 初始化====================
void usart0_init(void)
{
    rcu_periph_clock_enable(RCU_GPIOA);
    rcu_periph_clock_enable(RCU_USART0);

    // TX PA9
    gpio_init(GPIOA, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ, GPIO_PIN_9);

    // RX PA10
    gpio_init(GPIOA, GPIO_MODE_IPU, GPIO_OSPEED_50MHZ, GPIO_PIN_10);

    usart_baudrate_set(USART0, 9600);
    usart_word_length_set(USART0, USART_WL_8BIT);
    usart_stop_bit_set(USART0, USART_STB_1BIT);
    usart_parity_config(USART0, USART_PM_NONE);
    usart_receive_config(USART0, USART_RECEIVE_ENABLE);
    usart_transmit_config(USART0, USART_TRANSMIT_ENABLE);

    usart_enable(USART0);
}
//==================== 延时函数 ====================
void delay_ms(uint32_t ms)
{
    volatile uint32_t i, j;
    for(i = 0; i < ms; i++)
        for(j = 0; j < 3000; j++);
}

//==================== 生成PN码序列 ====================
void PN_generate(void)
{
    uint8_t reg = 0x1F;
    for(int i=0; i<PN_CODE_LEN; i++)
    {
        PN_Code[i] = reg & 1;
        uint8_t fb = ((reg >> 4) & 1) ^ ((reg >> 1) & 1);
        reg = (reg << 1) | fb;
    }

    for(int i=0; i<PN_CODE_LEN; i++)
        PN_BPSK[i] = PN_Code[i] ? 1 : -1;
}

//==================== 鎵╅ ====================
void DSSS_encode(uint8_t bit, uint8_t *chip_out)
{
    if(bit)
        for(int i=0; i<PN_CODE_LEN; i++) chip_out[i] = PN_Code[i];
    else
        for(int i=0; i<PN_CODE_LEN; i++) chip_out[i] = 1 - PN_Code[i];
}

//==================== 鐩稿叧杩愮畻 ====================
int32_t correlate(int8_t *a, int8_t *b, uint16_t len)
{
    int32_t sum = 0;
    for(int i=0; i<len; i++)
        sum += a[i] * b[i];
    return sum;
}

int32_t DSSS_score(uint8_t *chip_in)
{
    int8_t rx[PN_CODE_LEN];
    uint16_t i;

    for(i = 0; i < PN_CODE_LEN; i++)
    {
        rx[i] = chip_in[i] ? 1 : -1;
    }

    return correlate(rx, PN_BPSK, PN_CODE_LEN);
}

//==================== 瑙ｆ墿 ====================
uint8_t DSSS_decode(uint8_t *chip_in)
{
    int32_t corr = DSSS_score(chip_in);
    return corr > 0 ? 1 : 0;
}

// ===================== 銆愭柊澧炪€戜粠涓插彛璇?瀛楄妭 =====================
uint8_t usart_get_byte(void)
{
    while(usart_flag_get(USART0, USART_FLAG_RBNE) == RESET);
    return usart_data_receive(USART0);
}

void inject_chip_errors(uint8_t *chips, uint16_t len, uint8_t error_count)
{
    uint16_t i;

    for(i = 0; i < error_count && i < len; i++)
    {
        chips[i] ^= 1;
    }
}

uint32_t pseudo_rand(void)
{
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state;
}

void inject_noise_by_rate(uint8_t *chips, uint16_t len, uint8_t error_percent)
{
    uint16_t i;

    for(i = 0; i < len; i++)
    {
        if((pseudo_rand() % 100) < error_percent)
        {
            chips[i] ^= 1;
        }
    }
}


uint16_t find_preamble_offset(uint8_t *chips, uint16_t search_len)
{
    uint16_t offset;
    uint16_t best_offset = 0;
    int32_t best_score = -1000000;

    for(offset = 0; offset < search_len; offset++)
    {
        int32_t total_score = 0;
        uint16_t p;

        for(p = 0; p < PREAMBLE_LEN; p++)
        {
            int32_t score = DSSS_score(&chips[offset + p * PN_CODE_LEN]);

            if(PREAMBLE_BITS[p] == 1)
            {
                total_score += score;
            }
            else
            {
                total_score -= score;
            }
        }

        if(total_score > best_score)
        {
            best_score = total_score;
            best_offset = offset;
        }
    }

    return best_offset;
}
//==================== 瑙ｆ墿 ====================
void build_tx_frame(uint8_t tx_data, uint8_t *tx_stream)
{
    uint8_t chip_buf[PN_CODE_LEN];
    uint16_t p;
    int b;

    for(p = 0; p < PREAMBLE_LEN; p++)
    {
        DSSS_encode(PREAMBLE_BITS[p], chip_buf);
        memcpy(&tx_stream[p * PN_CODE_LEN], chip_buf, PN_CODE_LEN);
    }

    for(b = 0; b < PAYLOAD_BITS; b++)
    {
        uint8_t bit = (tx_data >> b) & 1;
        DSSS_encode(bit, chip_buf);
        memcpy(&tx_stream[(PREAMBLE_LEN + b) * PN_CODE_LEN], chip_buf, PN_CODE_LEN);
    }
}

uint16_t get_tx_frame_length(void)
{
    return FRAME_BITS * PN_CODE_LEN;
}

uint8_t get_tx_chip(uint8_t *tx_stream, uint16_t index)
{
    if(index >= get_tx_frame_length())
    {
        return 0;
    }

    return tx_stream[index];
}

void tx_start(uint8_t tx_data, uint8_t *tx_stream)
{
    build_tx_frame(tx_data, tx_stream);
    tx_active_stream = tx_stream;
    tx_chip_index = 0;
    tx_chip_length = get_tx_frame_length();
}

uint8_t tx_has_next_chip(void)
{
    if(tx_active_stream == NULL)
    {
        return 0;
    }

    return tx_chip_index < tx_chip_length;
}

uint8_t tx_get_next_chip(void)
{
    if(!tx_has_next_chip())
    {
        return 0;
    }

    return tx_active_stream[tx_chip_index++];
}

void send_one_frame(uint8_t tx_data)
{
    tx_start(tx_data, tx_stream);
}


uint8_t receive_one_frame(uint8_t *rx_stream, uint16_t *best_offset_out)
{
    uint8_t rx_data = 0;
    uint16_t best_offset;

    best_offset = find_preamble_offset(rx_stream, PN_CODE_LEN);

    for(int b = 0; b < PAYLOAD_BITS; b++)
    {
        uint8_t bit = DSSS_decode(&rx_stream[best_offset + (PREAMBLE_LEN + b) * PN_CODE_LEN]);
        rx_data |= (bit << b);
    }

    *best_offset_out = best_offset;
    return rx_data;
}

void prepare_simulated_rx_stream(uint16_t sync_offset, uint8_t error_percent)
{
    memset(rx_stream, 0, sizeof(rx_stream));
    memcpy(&rx_stream[sync_offset], tx_stream, FRAME_BITS * PN_CODE_LEN);
    inject_noise_by_rate(rx_stream, FRAME_BITS * PN_CODE_LEN + sync_offset, error_percent);
}

void prepare_real_rx_stream(void)
{
		//这里以后要接“真正的接收路径”
    memset(rx_stream, 0, sizeof(rx_stream));
}


void prepare_rx_stream(uint16_t sync_offset, uint8_t error_percent)
{
    if(g_rx_mode == RX_MODE_SIMULATION)
    {
        prepare_simulated_rx_stream(sync_offset, error_percent);
    }
    else
    {
        prepare_real_rx_stream();
    }
}




test_result_t run_dsss_test(uint8_t tx_data, uint8_t error_percent, uint16_t sync_offset)
{
    test_result_t result;
    uint16_t round;
    uint16_t best_offset;
    uint8_t rx_data;

    result.ok_count = 0;
    result.sync_ok_count = 0;
    result.data_ok_when_sync_ok = 0;
    result.last_best_offset = 0;

    for(round = 0; round < TEST_ROUNDS; round++)
    {
        rx_data = 0;
        send_one_frame(tx_data);

        prepare_rx_stream(sync_offset, error_percent);


        rx_data = receive_one_frame(rx_stream, &best_offset);

        if(best_offset == sync_offset)
        {
            result.sync_ok_count++;
        }

        if(tx_data == rx_data)
        {
            result.ok_count++;

            if(best_offset == sync_offset)
            {
                result.data_ok_when_sync_ok++;
            }
        }

        result.last_best_offset = best_offset;
    }

    return result;
}


int main(void)
{
		uint8_t tx_data;
		uint8_t error_percent = 30;
		uint16_t sync_offset = 10;
		test_result_t result;

		uint8_t rx_data;
		uint16_t best_offset;

    // 鍒濆鍖?
    system_init();
    usart0_init();
    PN_generate();
    delay_ms(100);

    printf("==== GD32E503 DSSS Modem V1 ====\r\n");
		printf("Input 1 byte from USART.\r\n");
		printf("Waiting for data...\r\n");

    // ==========================================
    // Read one byte from USART, for example 0xAB or 0xFF.
    // ==========================================
   
		
    while(1)
		{
		tx_data = usart_get_byte();
			if(tx_data == 0x0D || tx_data == 0x0A)
			{
				continue;
			}

		rng_state = tx_data + 1;
		send_one_frame(tx_data);

    printf("\r\n[New Frame]\r\n");
		printf("TX byte: 0x%02X\r\n", tx_data);
		if(g_rx_mode == RX_MODE_SIMULATION)
		{
			printf("RX mode: simulation\r\n");
		}
			else
		{
			printf("RX mode: real\r\n");
		}

		if(g_app_mode == APP_MODE_TEST)
		{
			printf("APP mode: test\r\n");
		}
		else
		{
			printf("APP mode: work\r\n");
		}

		
		printf("Noise setting: %d%%\r\n", error_percent);
		printf("Frame length: %d chips\r\n", get_tx_frame_length());

		printf("TX preview: ");
		for(uint16_t i = 0; i < 16 && tx_has_next_chip(); i++)
		{
			printf("%d", tx_get_next_chip());
		}
		printf("\r\n");
		if(g_app_mode == APP_MODE_TEST)
		{
			result = run_dsss_test(tx_data, error_percent, sync_offset);

			printf("Frame test result: %d / %d\r\n", result.ok_count, TEST_ROUNDS);
			printf("Sync offset set: %d\r\n", sync_offset);
			printf("Best offset: %d\r\n", result.last_best_offset);
			printf("Sync success: %d / %d\r\n", result.sync_ok_count, TEST_ROUNDS);
			printf("Data success with correct sync: %d / %d\r\n", result.data_ok_when_sync_ok, result.sync_ok_count);
		}
		else
		{
				if(g_rx_mode == RX_MODE_REAL)
				{
						printf("Work mode real RX is not implemented yet.\r\n");
						printf("Waiting for next data...\r\n");
						continue;
				}

				prepare_rx_stream(sync_offset, error_percent);
				rx_data = receive_one_frame(rx_stream, &best_offset);

				printf("RX byte: 0x%02X\r\n", rx_data);
				printf("Best offset: %d\r\n", best_offset);
		}

		printf("Waiting for next data...\r\n");



		}
   
}
