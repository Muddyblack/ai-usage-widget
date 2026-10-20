cmake_minimum_required(VERSION 3.20)
project(tidesi-tray LANGUAGES CXX)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

qt_add_executable(tidesi-tray main.cpp)
target_link_libraries(tidesi-tray PRIVATE Qt6::Widgets)
target_compile_features(tidesi-tray PRIVATE cxx_std_17)

install(TARGETS tidesi-tray RUNTIME DESTINATION bin)
