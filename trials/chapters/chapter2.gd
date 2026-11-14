extends RefCounted
# Trials bölüm dosyası / chapter file. Only edit the text between the triple quotes below.
# Format reference: res://trials/AUTHORING.md   Validate: tools/trials/validate.sh trials/chapters/chapter2.gd
# Demo: vines (wall jumps), wide room with scrolling camera, darkness chase (Manager_Darkness), ceiling spikes, collectible, exit.
const TEXT := r"""
title: Hollow Run
subtitle: demo chapter - replace with the real one
theme: cave

[room hollow]
name: Vine Wall
at: 0 0
######################
#....................#
#....c...............#
#..........|##.......#
#..........|##.......#
#..........|##.......#
#..........|##.......#
#..........|##.......#
#..........|##........
#.P..^^....|##........
######################

[room run]
name: The Dark Follows
at: hollow right bottom
chase: medium
chase_delay: 0.8
######################################
#....................................#
#....................................#
#....................................#
#..........###.......................#
#..........vvv.............c.........#
#....................................#
.....................................#
.D.P.......^^..........^^.........E..#
######################################
"""
