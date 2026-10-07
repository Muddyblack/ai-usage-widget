cmake_minimum_required(VERSION 3.20)
project(ai-usage-tray LANGUAGES CXX)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

qt_add_executable(ai-usage-tray main.cpp)
target_link_libraries(ai-usage-tray PRIVATE Qt6::Widgets)
target_compile_features(ai-usage-tray PRIVATE cxx_std_17)

install(TARGETS ai-usage-tray RUNTIME DESTINATION bin)
