extends RefCounted
# Trials bölüm dosyası / chapter file. Only edit the text between the triple quotes below.
# Format reference: res://trials/AUTHORING.md   Validate: tools/trials/validate.sh trials/chapters/chapter1.gd
# Demo: jump, spikes (4 orientations), one-way platform, moving platform, dash orb, jump orb, enemy, hazard (x), pit, lamp, collectible, exit.
const TEXT := r"""
title: Thornwood Path
subtitle: demo chapter - replace with the real one
theme: forest

[room start]
name: First Steps
at: 0 0
####################
#..................#
#..................#
#..................#
#............c.....#
#...........=====..#
#...................
#...................
#.P....^^..........#
####################

[room climb]
name: Lift
at: start right bottom
platform_speed: 120
platform_wait: 1.0
####################
#..................#
#...c...............
#...................
#..........#########
#......m...#########
#>...*.....#########
#>.........#########
#>.........#########
#..........#########
...........#########
...P...M...#########
#####...############
#####xxx############

[room gate]
name: The Gap
at: climb right 0
##########################
#........................#
.........................#
.P........o..........L.E.#
######.........###########
######........<###########
######...e....<###########
######..####...###########
######..vvvv...###########
######^^^^^^^^^###########
##########################
"""
