set(SRC_Files UserEOSModel.cpp UserStrengthModel.cpp init_state_vars.cpp)
add_library(user_material_models OBJECT ${SRC_Files})
target_include_directories(user_material_models PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(user_material_models Elements)
