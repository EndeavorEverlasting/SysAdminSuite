cmake_minimum_required(VERSION 3.20)
project(SysAdminSuiteMappingNative LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(MSVC)
  add_compile_options(/W4 /permissive- /utf-8)
endif()

add_library(mapping_common STATIC
  src/common/json_util.cpp
  src/common/path_util.cpp
  src/common/string_util.cpp
)
target_include_directories(mapping_common PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_executable(SysAdminSuite.Mapping.Worker
  src/worker/WorkerMain.cpp
  src/worker/registry_unc.cpp
  src/worker/printers.cpp
  src/worker/print_ops.cpp
  src/worker/artifacts.cpp
  src/worker/run_control.cpp
  src/worker/result_rows.cpp
  src/worker/default_printer_task.cpp
)
target_link_libraries(SysAdminSuite.Mapping.Worker PRIVATE mapping_common)
target_link_libraries(SysAdminSuite.Mapping.Worker PRIVATE advapi32 winspool shell32 user32 ole32 oleaut32 taskschd)

add_executable(SysAdminSuite.Mapping.Controller
  src/controller/ControllerMain.cpp
)
target_link_libraries(SysAdminSuite.Mapping.Controller PRIVATE mapping_common)
target_link_libraries(SysAdminSuite.Mapping.Controller PRIVATE advapi32 shell32 user32)

foreach(_t SysAdminSuite.Mapping.Worker SysAdminSuite.Mapping.Controller)
  set_target_properties(${_t} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/$<CONFIG>"
  )
endforeach()

# --- Unit tests (GoogleTest) ---
option(MAPPING_NATIVE_BUILD_TESTS "Build native mapping unit tests" ON)
if(MAPPING_NATIVE_BUILD_TESTS)
  include(FetchContent)
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
  set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
  FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.14.0
  )
  FetchContent_MakeAvailable(googletest)

  enable_testing()
  add_executable(mapping_native_tests
    tests/mapping_common_test.cpp
    src/worker/result_rows.cpp
  )
  target_include_directories(mapping_native_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  target_link_libraries(mapping_native_tests PRIVATE mapping_common GTest::gtest_main)
  if(MSVC)
    target_compile_options(mapping_native_tests PRIVATE /utf-8)
  endif()

  add_test(NAME mapping_native_tests COMMAND mapping_native_tests
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
endif()
