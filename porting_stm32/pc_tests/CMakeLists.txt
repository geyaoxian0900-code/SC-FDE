cmake_minimum_required(VERSION 3.10)
project(scfde_pc_tests C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

# Firmware algorithm sources are compiled directly (single source of truth).
set(FIRMWARE_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../GD32E503C_START_Demo_Suites/Projects/02_SC_FDE_UWA_MODEM")

set(SCFDE_CORE_SOURCES
    ${FIRMWARE_DIR}/scfde_fft.c
    ${FIRMWARE_DIR}/scfde_ldpc.c
    ${FIRMWARE_DIR}/scfde_equalizer.c
    ${FIRMWARE_DIR}/scfde_modem.c
    ${FIRMWARE_DIR}/scfde_turbo.c
    ${FIRMWARE_DIR}/scfde_cck.c
    ${FIRMWARE_DIR}/scfde_csk.c
    ${FIRMWARE_DIR}/scfde_protocol.c
)

# Platform-independent algorithm library (public API tests link against it).
add_library(scfde_core STATIC ${SCFDE_CORE_SOURCES})
target_include_directories(scfde_core PUBLIC ${FIRMWARE_DIR})
target_link_libraries(scfde_core m)

enable_testing()

function(add_scfde_test name)
    add_executable(${name} ${name}.c)
    target_link_libraries(${name} scfde_core m)
    add_test(NAME ${name} COMMAND ${name})
endfunction()

add_scfde_test(test_fft)          # FFT/IFFT round trip and known transforms
add_scfde_test(test_ldpc)         # LDPC encode/decode and error correction
add_scfde_test(test_equalizer)    # MMSE/ZF/MF/IB-DFE/NLMS on synthetic channel
add_scfde_test(test_fblms)         # FBLMS constrained-weight convergence
add_scfde_test(test_end_to_end)   # full digital loopback, all equalizer modes
add_scfde_test(test_turbo)         # conv code + interleaver + BCJR + turbo loopback
add_scfde_test(test_cck)          # CCK modem loopback, all 7 receivers
add_scfde_test(test_csk)          # CSK modem loopback, all 3 receivers
add_scfde_test(test_protocol)     # MAC protocol: frame tags + slot voting

# Static-include tests compile the firmware sources themselves and therefore
# must not link scfde_core (duplicate symbols).
function(add_included_test name)
    add_executable(${name} ${name}.c)
    target_include_directories(${name} PRIVATE ${FIRMWARE_DIR})
    target_link_libraries(${name} m)
    add_test(NAME ${name} COMMAND ${name})
endfunction()

add_included_test(test_crc)       # CRC-16/CCITT known vector + golden packet
add_included_test(test_sync)      # sync start / CFO estimation with known offsets

# Golden-vector exporter: includes the firmware sources with the `static`
# include trick so every internal stage can be dumped directly.
add_executable(test_export_golden test_export_golden.c)
target_include_directories(test_export_golden PRIVATE ${FIRMWARE_DIR})
target_link_libraries(test_export_golden m)

add_test(NAME test_export_golden
         COMMAND test_export_golden
         ${CMAKE_CURRENT_SOURCE_DIR}/../golden_vectors/c_export)
