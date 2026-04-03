Village World 3D Minimal Pack
=============================

Что это
-------
Это минимальный 3D graybox-пак для локальной карты деревни.
Он собран как стартовый набор под фиксированную изометрическую камеру
и клеточную логику карты. Это не финальный арт, а рабочие заглушки,
которые помогают быстрее подключить генератор, рендер карты и проверить читаемость.

Что входит
----------
- 34 GLB-модели
- 4 PNG-наложения для служебных слоёв
- 2 PNG-теневые маски
- manifest.json
- preview/preview_sheet.png

Стиль набора
------------
- минималистичный 3D
- монохромная серо-белая гамма
- светлая почти белая база
- низкий визуальный шум
- крупные читаемые формы
- без реалистичных материалов и без бумажной желтизны

Структура папок
---------------
environment/
  terrain/
    ground/
    clearing/
    road/
  boundaries/
    forest/
    rock/
    water/
    ravine/
  transitions/
  props/
    major/
  overlays/
preview/
shadows/

Сетка и размеры
---------------
- базовая клетка: 2.0 x 2.0 world units (юнитов мира)
- вертикальная ось: Y
- terrain-модули стоят на Y=0
- pivot (точка опоры) у модулей: center_bottom (центр снизу)

Состав минимального набора
--------------------------
Terrain:
- ground_01..03
- clearing_01..02
- road_narrow_straight
- road_narrow_corner
- road_medium_straight
- road_medium_t
- road_wide_straight

Boundaries:
- forest_edge_straight
- forest_edge_corner
- forest_edge_sparse
- rock_edge_straight
- rock_edge_corner
- rock_edge_ridge
- water_edge_straight
- water_edge_corner
- water_channel
- ravine_edge_straight
- ravine_edge_corner
- ravine_narrow_pass

Transitions:
- road_to_ground_soft
- clearing_to_ground_soft
- obstacle_transition_rock
- obstacle_transition_forest

Props:
- boulder_large
- stump_wide
- dead_tree_a
- dead_tree_b
- ruins_fragment
- broken_fence_segment
- cart_fragment
- log_pile

Overlays:
- buildable_mask.png
- threat_heat.png
- height_tint.png
- entry_marker.png

Shadows:
- shadow_boulder_large.png
- shadow_dead_tree.png

Ограничения
-----------
- Это стартовый production-blockout (производственный блок-аут), а не финальный визуал.
- Дороги и границы пока даны в минимальном наборе модулей, без полного библиотеки всех углов,
  развилок и вариаций.
- Поверхности собраны как простая геометрия с однотонными материалами.
- Для финального вида нужен второй проход по силуэтам, материалам и консистентности модулей.

Рекомендуемый следующий шаг
---------------------------
После подключения в проект стоит расширить набор в таком порядке:
1. ещё 2-3 вариации ground и clearing;
2. дорожные модули развилки, сужения, расширения;
3. внутренние и внешние углы для всех boundaries;
4. ресурсные кластеры;
5. крупные ориентиры местности.
