cmake_minimum_required(VERSION 3.14)
project(UniswapUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# SOURCES must be listed explicitly — the macro does not glob.
logos_module(
    NAME uniswap_ui
    REP_FILE src/uniswap_ui.rep
    SOURCES
        src/uniswap_ui_backend.h
        src/uniswap_ui_backend.cpp
        src/uniswap_ui_apply.h
        src/uniswap_ui_guard.h
        src/uniswap_ui_scope.h
    INCLUDE_DIRS
        src
)
