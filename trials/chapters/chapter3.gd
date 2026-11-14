extends RefCounted
# Trials bölüm dosyası / chapter file. Only edit the text between the triple quotes below.
# Format reference: res://trials/AUTHORING.md   Validate: tools/trials/validate.sh trials/chapters/chapter3.gd
# Demo: dark rooms (lantern), ambient darkness drain with heal lamps as checkpoints, vines, jump orb, one-way platform, collectible, exit.
const TEXT := r"""
title: Lanternless Deep
subtitle: demo chapter - replace with the real one
theme: deep

[room dim]
name: Low Light
at: 0 0
dark: yes
########################
#......................#
#......................#
#......................#
#...............c......#
#..............===.....#
#.......................
#..........o............
#.P...^^........^^.....#
########################

[room drain]
name: Cold Air
at: dim right 0
dark: yes
drain: yes
########################
#......................#
#......................#
#......................#
#........|##...........#
#........|##...........#
.........|##...........#
.........|##...........#
#.P..L...|##.....L..E..#
########################
"""
