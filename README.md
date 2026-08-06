# SC-FDE 姘村０鍗曡浇娉㈤鍩熷潎琛￠€氫俊绯荤粺

鍩轰簬 GD32E503 鐨勬按澹板崟杞芥尝棰戝煙鍧囪　锛圫C-FDE锛夐€氫俊椤圭洰锛屽寘鍚細

- **GD32 鍥轰欢**锛氬畬鏁寸殑 SC-FDE 姘村０璋冨埗瑙ｈ皟鍣紙璋冨埗/鍚屾/鍧囪　/LDPC/涓插彛搴旂敤锛?- **MATLAB 浠跨湡**锛氬鐓ф暀鏉愩€婂崟杞芥尝姘村０閫氫俊鎶€鏈€嬪叚绔犵殑鍏紡绾т豢鐪燂紙绾?1.9 涓囪浠ｇ爜锛?- **STM32 绉绘宸ヤ綔鍖?*锛氱畻娉曢粍閲戝悜閲忋€丳C 鍗曞厓娴嬭瘯銆佺‖浠跺洖鐜獙璇?
---

## 鐩綍缁撴瀯

```
鈹溾攢鈹€ GD32E503C_START_Demo_Suites/
鈹?  鈹斺攢鈹€ Projects/
鈹?      鈹溾攢鈹€ 01_GPIO_Running_LED/           LED 绀轰緥
鈹?      鈹斺攢鈹€ 02_SC_FDE_UWA_MODEM/            SC-FDE 姘村０璋冨埗瑙ｈ皟鍣ㄥ浐浠?鈹溾攢鈹€ GD32E50x_Firmware_Library/              GD32 鏍囧噯澶栬搴?鈹溾攢鈹€ papers/                                 MATLAB 浠跨湡宸ョ▼锛堜富宸ヤ綔鍖猴級
鈹?  鈹溾攢鈹€ run_all_simulations.m               璁烘枃澶嶇幇缁熶竴鎵瑰鐞嗗叆鍙?鈹?  鈹溾攢鈹€ run_unified_equalizer.m             鍧囪　鍣ㄧ粺涓€杩愯鍏ュ彛锛? 鍦烘櫙锛?鈹?  鈹溾攢鈹€ run_unified_equalizer_interactive.m 鍧囪　鍣ㄤ氦浜掑紡閫夋嫨鍣?鈹?  鈹溾攢鈹€ modules/+scfde/                     妯″潡鍖栨祦姘寸嚎涓庡潎琛″櫒鍖?鈹?  鈹溾攢鈹€ chapter2~6_simulation/              鍚勭珷璁烘枃澶嶇幇涓庣粨鏋?鈹?  鈹溾攢鈹€ engineering_simulation/             MCU 閰嶅浠跨湡锛堥粍閲戞ā鍨嬶級
鈹?  鈹溾攢鈹€ common/                             LDPC 缂栬В鐮佸叡鐢?鈹?  鈹溾攢鈹€ examples/                           妯″潡鏇挎崲绀轰緥
鈹?  鈹斺攢鈹€ tests/                              鍥炲綊娴嬭瘯
鈹溾攢鈹€ porting_stm32/                          STM32 绉绘宸ヤ綔鍖?鈹?  鈹溾攢鈹€ AUDIT_REPORT.md                     绉绘瀹¤鎶ュ憡
鈹?  鈹溾攢鈹€ golden_vectors/                     榛勯噾鍚戦噺锛圡ATLAB + C 鍙屼晶锛?鈹?  鈹溾攢鈹€ pc_tests/                           PC 绔?C 鍗曞厓娴嬭瘯锛圕Make锛?鈹?  鈹溾攢鈹€ hardware/                           鍗曟澘鍥炵幆娴嬭瘯
鈹?  鈹斺攢鈹€ twoboard/                           鍙屾澘瀵规祴鏂规
鈹溾攢鈹€ book/                                   鏁欐潗銆婂崟杞芥尝姘村０閫氫俊鎶€鏈€嬫埅鍥?鈹斺攢鈹€ results/                                纭欢鍥炵幆瀹炴祴璁板綍
```

---

## 涓€銆丟D32 鍥轰欢锛?2_SC_FDE_UWA_MODEM锛?
骞冲彴鏃犲叧绠楁硶灞傦紙4 涓枃浠讹紝绾?1090 琛岋紝鍙洿鎺ョЩ妞嶅埌浠绘剰骞冲彴锛夛細

| 鏂囦欢 | 鍔熻兘 |
|---|---|
| `scfde_modem.c` | 甯х粍瑁呫€乁W 鍙岀浉鍏冲悓姝ャ€丆FO 浼拌銆丩S 淇￠亾浼拌銆丆RC-16銆佽В鐮佽皟搴?|
| `scfde_equalizer.c` | MMSE/ZF/MF 棰戝煙鍧囪　銆両B-DFE銆丯LMS-TDE |
| `scfde_ldpc.c` | LDPC(192,128) 缂栫爜 + 鍒嗗眰褰掍竴鍖栨渶灏忓拰璇戠爜 |
| `scfde_fft.c` | radix-2 FFT/IFFT锛?2/128 鐐癸級 |

BSP 灞傦紙GD32 骞冲彴锛夛細DAC 鍙戝皠锛?6kHz锛夈€丄DC 鎺ユ敹锛?8kHz锛夈€乁SART 涓插彛鑿滃崟銆佸崐鍙屽伐鎺у埗銆?
> 娉ㄦ剰锛歚scfde_ldpc.c` 鐨?QC-LDPC 鏋勯€犲瓨鍦?d_min=2 缂洪櫡锛堢籂閿欑巼绾?33%锛夛紝鍩虹嚎榛樿鍏抽棴 LDPC锛坄SCFDE_LDPC_ENABLED=0`锛夛紝閲嶆柊鍚敤鍓嶉渶閲嶈璁＄爜銆?
---

## 浜屻€丮ATLAB 浠跨湡锛坧apers/锛?
### 璁烘枃澶嶇幇

瀵圭収銆婂崟杞芥尝姘村０閫氫俊鎶€鏈€嬪叚绔狅紝鍏ㄩ儴鏍稿績鍏紡瀹炵幇骞堕檮鑷牎楠岋細

| 绔?| 鍐呭 | 鍏抽敭瀹炵幇 |
|---|---|---|
| 2 | 鍗曡浇娉㈡椂鍩熷潎琛?| LMS/NLMS/RLS-DFE銆丏PLL 鐩镐綅璺熻釜銆丳TR 鏃跺弽銆佸瓙甯?PTR |
| 3 | 鍗曡浇娉㈤鍩熷潎琛?| ZF/MMSE-FDE銆丠TFDE銆丼D/HD-IBDFE銆両CE 杩唬淇￠亾浼拌銆丆P/ZP/UW |
| 4 | 鍗曡浇娉㈣凯浠ｅ潎琛?| BCJR锛圡AP/Log-MAP/Max-Log-MAP锛夈€丗D-Turbo銆乀F-Turbo銆丅LMS銆丗DDA-TEQ |
| 5 | 浜掕ˉ鐮侀敭鎺ф墿棰?| CCK/GCCK 鐮佹湰銆丷ake銆丏FE銆佸弻鍚?DFE銆乀R 鍒嗛泦銆丆CK-SM MIMO-IBDFE |
| 6 | 寰幆绉讳綅鎵╅ | CSK 鐩稿叧妫€娴嬨€佽蒋 PIC/SIC銆丒SE 杩唬銆丆SK-IDMA |

```matlab
cd papers
run_all_simulations                       % 鍏ㄩ儴 11 涓疄楠岋紙quick 妗ｏ級
run_all_simulations(struct("profile","full"))
```

### 鍧囪　鍣ㄥ嵆鎻掑嵆鐢紙36 涓級

鎵€鏈?6 绔犲潎琛″櫒缁熶竴濂戠害涓?`receiver = equalizer(channel, source, cfg)`锛岄€氳繃 `cfg.equalizers` 浠绘剰閫夋嫨/娣风敤锛?
```matlab
% 缁熶竴鍏ュ彛锛? 绉嶅満鏅紙qpsk/turbo/cck/csk锛?r = run_unified_equalizer(struct("equalizers", "all"));
r = run_unified_equalizer(struct("equalizers", ["htfde","cck-rake","csk-ese"], ...
    "scenario", "auto"));

% 浜や簰寮忛€夋嫨鍣細鑿滃崟缂栧彿閫夋嫨
run_unified_equalizer_interactive

% 鑷畾涔夊潎琛″櫒锛堝彧闇€婊¤冻濂戠害锛?cfg.equalizers = @my_equalizer;
```

鍐呯疆鍧囪　鍣ㄦ竻鍗曪紙`modules/+scfde/equalizer_registry.m`锛夛細

- 绗?绔狅紙10锛夛細dfe, lms-dfe, nlms-dfe, rls-dfe, dpll-dfe, mc-lms-dfe, mc-nlms-dfe, mc-rls-dfe, ptr-dfe, subband-ptr-dfe
- 绗?绔狅紙7锛夛細mmse-fde, zf-fde, htfde, sd-ibdfe, hd-ibdfe, ice-sd-ibdfe, ice-hd-ibdfe
- 绗?绔狅紙9锛夛細td-turbo, fd-dfe, fd-turbo, tf-turbo, bitf-turbo, blms-tf-turbo, tdda-teq, fdda-teq, fdda-dfe-teq
- 绗?绔狅紙7锛夛細cck-rake, cck-dfe, cck-bidfe, cck-bidfe2, cck-tr-diversity, cck-fde, cck-mfb
- 绗?绔狅紙3锛夛細csk-matched-filter, csk-soft-sic, csk-ese

### 妯″潡鍖栨祦姘寸嚎

```text
source(cfg) 鈫?channel(tx,cfg) 鈫?receiverBank(channel,source,cfg) 鈫?metric(receiver,source,cfg)
```

妯″潡閫氳繃鍑芥暟鍙ユ焺娉ㄥ叆锛坄modules/+scfde/default_modules.m`锛夛紝鍙暣浣撴浛鎹紙瑙?`examples/`锛夈€?
---

## 涓夈€丼TM32 绉绘锛坧orting_stm32/锛?
| 鐩綍 | 鍐呭 |
|---|---|
| `AUDIT_REPORT.md` | 璇︾粏瀹¤锛?6 椤瑰姛鑳芥牳瀹炪€?1 椤瑰弬鏁颁竴鑷存€х煩闃点€丳1-P15 闂娓呭崟 |
| `golden_vectors/` | 23 闃舵榛勯噾鍚戦噺锛圡ATLAB 涓?C 鍙屼晶瀵煎嚭锛屽凡鐢熸垚锛?|
| `pc_tests/` | CMake 宸ョ▼鐩存帴缂栬瘧鍥轰欢绠楁硶婧愮爜锛? 涓祴璇曞叏杩?|
| `compare/` | 榛勯噾鍚戦噺鑷姩姣斿鑴氭湰 |
| `hardware/` | 鍗曟澘鏁板瓧鍥炵幆娴嬭瘯锛?00/300 甯?CRC 閫氳繃锛?|
| `twoboard/` | 鍙屾澘瀵规祴鏂规涓庤剼鏈?|

---

## 鍥涖€佺‖浠跺疄娴?
`results/` 璁板綍鍗曟澘鏁板瓧鍥炵幆锛圕OM6 @9600锛屾瘡鎵?300 甯э級锛?
- 300/300 甯?CRC 鍏ㄨ繃锛孎ER=0锛屽悓姝ュ害閲?0.999锛孋FO=0Hz
- 鍧囪　鍣細MMSE-FDE锛涜浇鑽凤細`SC-FDE` 鏂囨湰

---

## 浜斻€佽繍琛岃姹?
- **MATLAB**锛歊2023a 鎴栨洿鏂帮紙浣跨敤 string 鏁扮粍銆乤rguments 鍧椼€乪xportgraphics锛?- **GD32 鍥轰欢**锛欿eil MDK锛圙D32E503C_START 宸ョ▼锛?- **PC 娴嬭瘯**锛欳Make 鈮?3.10 + GCC锛堟敮鎸?C99锛?
---

## 鍏€佸凡鐭ラ檺鍒?
1. LDPC(192,128) 鐮佹瀯閫犵己闄凤紙d_min=2锛夛紝宸查粯璁ゅ叧闂?2. 鍚屾+CFO 浼拌鏈夋晥鑼冨洿绾?卤10Hz锛園4ksym锛?2kHz 杞芥尝锛夛紝绉诲姩骞冲彴闇€瀹藉甫澶氭櫘鍕掕ˉ鍋?3. C 渚ф棤 RRC 鎴愬舰锛堢煩褰㈣剦鍐诧級锛屽彂灏勯璋辨瘮 MATLAB锛圧RC 0.35锛夊绾?50%
4. 浠跨湡鐢ㄥ悎鎴愪俊閬擄紙Bellhop 鍙€夛級锛屾湭鍚疄娴嬫按澹颁俊閬撴暟鎹?5. CCK 鍙屽悜 DFE锛坆i1/bi2锛変笌 TR 鍒嗛泦鍦ㄧ煭甯т笅瀛樺湪杈圭晫鎬ц兘鎹熷け锛堜笌鍘熷疄鐜颁竴鑷达級

## 涓冦€佸璁¤鏄庯紙2026-08 鍏紡绾у璁★級

鎸?浠ｆ暟褰㈠紡绛変环 / 鐘舵€佷笌杈圭晫鏉′欢涓€鑷?/ 鍙傛暟鐢卞叕寮忔帹瀵?涓夊眰娆″璁＄粨璁猴細

- **鍏紡瀵瑰簲鎬?*锛歚run_all_simulations` 鐨?`paper.chapter2/3/4` 澶嶇幇鐨勬槸 Yang Siqi 璁烘枃鐨?  **瓒嬪娍**锛岀珷鑺傜紪鍙凤紙鍥?3.2-3.10銆佸浘 4.2-4.8锛変笌鏁欐潗銆婂崟杞芥尝姘村０閫氫俊鎶€鏈€嬬殑鍏紡缂栧彿
  **涓嶄竴涓€瀵瑰簲**锛堝鏁欐潗寮?3-1 鏄暟鎹潡鍚戦噺瀹氫箟锛岃€岄」鐩浘 3.2/3.3 浣跨敤 UW 鍙岀浉鍏冲畾鏃跺害閲忥級銆?  鎵€鏈?`paper.*` 瀹為獙宸插湪娉ㄩ噴涓幓闄よ瀵兼€х殑鏁欐潗鍏紡缂栧彿寮曠敤锛屼粎淇濈暀"璁烘枃瓒嬪娍澶嶇幇"瀹氫綅銆?- **宸叉寜瀹¤淇**锛?  - 鍥?3.7-3.10 鐨勪及璁¤宸洸绾跨敱"鍙傛暟鍖栧櫔澹版ā鍨?鏀逛负**鐪熷疄淇″彿绾т及璁″櫒**
    锛堣繃閲囨牱 UW 鐩稿叧鑱斿悎鎼滅储锛屽紡 3-9~3-15 璇箟锛?  - 绗?4 绔?LDPC 杈撳叆鍣０鏂瑰樊鐢辩粡楠岀缉鏀撅紙0.75/0.85/0.35锛夋敼涓?*鍧囪　鍚庤В鏋愭畫浣欐柟宸?*
    `蟽_w虏路mean(|W|虏)`
  - 瀛愰樀 PTR 鐢?棰戝甫姝ｅ垯鍖栭€嗘护娉?鏀逛负**绾椂鍙嶅尮閰嶆护娉?*锛堝紡 2-48 璇箟锛?  - 鎵╁睍 CCK锛?6/32 鐮佺墖锛変慨澶嶈皟鐢ㄤ笉瀛樺湪鐨?`extend_scfde` 鍖呴棶棰?  - FD-DFE/IBDFE 楂?SNR 鏂█浠?蹇呴』鏇翠紭"鏀惧涓?涓嶅緱鏄捐憲鍔ｅ寲"锛圡MSE 宸叉敹鏁涙椂
    鍙嶉鏃犲鐩婂睘姝ｅ父锛?- **浠嶄负宸ョ▼杩戜技**锛堥潪閫愬紡鍘熸牱锛夛細HTFDE 鍙潬搴︾缉鏀俱€丅LMS 鐢ㄥ惊鐜潡鏇夸唬 overlap-save銆?  CCK Turbo 澶栫爜鐢ㄩ噸澶嶇爜鏇夸唬瀹屾暣缂栫爜銆?.5 鑺傚悎鎴?11 寰勪俊閬撱€丳IC/ESE 闃诲凹绯绘暟銆?