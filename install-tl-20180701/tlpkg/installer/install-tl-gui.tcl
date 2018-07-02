#!/usr/bin/env wish

# Copyright 2018 Siep Kroonenberg

# This file is licensed under the GNU General Public License version 2
# or any later version.

# Tcl/Tk wrapper for TeX Live installer

# Installation can be divided into three stages:
#
# 1. preliminaries. This stage may involve some interaction with the user,
#    which can be channeled through message boxes
# 2. a menu
# 3. the actual installation
#
# During stage 1. and 3. this wrapper collects stdout and stderr from
# the perl installer, with stderr being redirected to stdout.
# This output will be displayed in a text widget during stage 3,
# and in debug mode also in stage 1.
# During stage 3, we shall use event-driven, non-blocking I/O, which is
# needed for a scrolling display of installer output.
#
# Main window:
# filled successively with:
# - a logo, and 'loading...' label, by way of splash
# - a menu for stage 2
# - a log text widget for tracking stage 3
#   ::out_log should be cleared before stage 3.
#
# In profile mode, the menu stage is skipped.

package require Tk

# security: disable send
catch {rename send {}}

# menus: disable tearoff feature
option add *Menu.tearOff 0

# no bold text for messages; `userDefault' indicates priority
option add *Dialog.msg.font TkDefaultFont userDefault

# larger font
font create lfont {*}[font configure TkDefaultFont]
font configure lfont -size [expr {round(1.2 * [font actual lfont -size])}]

## italicized items; not used
#font create it_font {*}[font configure TkDefaultFont]
#font configure it_font -slant italic

### initialize some globals ###

# perl installer process id
set ::perlpid 0

# global variable for dialogs
set ::dialog_ans {}

set ::plain_unix 0
if {$::tcl_platform(platform) eq "unix" && $::tcl_platform(os) ne "Darwin"} {
  set ::plain_unix 1
}

# for help output
set ::env(NOPERLDOC) 1

set ::out_log {}; # list of strings

# this file should be in $::instroot/tlpkg/installer.
# at the next release, it may be better to start the installer, perl or tcl,
# from a shell wrapper, also on unix-like platforms
# this allows automatic inclusion of '--' parameter to separate
# tcl parameters from script parameters
set ::instroot [file normalize [info script]]
set ::instroot [file dirname [file dirname [file dirname $::instroot]]]

set ::perlbin "perl"
if {$::tcl_platform(platform) eq "windows"} {
  set ::perlbin "${::instroot}/tlpkg/tlperl/bin/perl.exe"
}

### procedures, mostly organized bottom-up ###

proc get_stacktrace {} {
  set level [info level]
  set s ""
  for {set i 1} {$i < $level} {incr i} {
    append s [format "Level %u: %s\n" $i [info level $i]]
  }
  return $s
} ; # get_stacktrace

# for debugging frontend-backend communication:
# write to a logfile which is shared with the backend.
# both parties open, append and close every time.

if {$::tcl_platform(platform) eq "unix" && $::tcl_platform(os) eq "Darwin"} {
  set ::dblfile "$::env(TMPDIR)/dblog"
} elseif {$::tcl_platform(platform) eq "unix"} {
  set ::dblfile "/tmp/dblog"
} else {
  set ::dblfile "$::env(TEMP)/dblog.txt"
}
proc dblog {s} {
  set db [open $::dblfile a]
  set t [get_stacktrace]
  puts $db "TCL: $s\n$t"
  close $db
}

# what exit procs do we need?
# - plain error exit with messagebox and stacktrace
# - plain messagebox exit
# - showing log output, maybe with appended message,
#   use log toplevel for lengthy output
# is closing the pipe $::inst guaranteed to kill perl? It should be

proc err_exit {{mess ""}} {
  if {$mess eq ""} {set mess "Error"}
  append mess "\n" [get_stacktrace]
  tk_messageBox -icon error -message $mess
  # kill perl process, just in case
  if $::perlpid {
    if {$::tcl_platform(platform) eq "unix"} {
      exec -ignorestderr "kill" $::perlpid
    } else {
      exec -ignorestderr "taskkill" "/pid" $::perlpid
    }
  }
  exit
} ; # err_exit

# regular read_line
proc read_line {} {
  if [catch {chan gets $::inst l} len] {
    # catch [chan close $::inst]
    err_exit "Error while reading from Perl backend"
  } elseif {$len < 0} {
    # catch [chan close $::inst]
    return [list -1 ""]
  } else {
    return [list $len $l]
  }
}; # read_line

proc read_line_no_eof {} {
  set ll [read_line]
  if {[lindex $ll 0] < 0} {
    log_exit "Unexpected closed backend"
  }
  set l [lindex $ll 1]
  # TODO: test under debug mode
  return $l
}; # read_line_no_eof

# non-blocking i/o: callback for "readable" during stage 3, installation
# ::out_log should no longer be needed
proc read_line_cb {} {
  set l "" ; # will contain the line to be read
  if {([catch {chan gets $::inst l} len] || [chan eof $::inst])} {
    catch {chan close $::inst}
    # note. the right way to terminate is terminating the GUI shell.
    # This closes stdin of the child
    puts stderr "read_line_cb: pipe no longer readable"
    .close configure -state !disabled
  } elseif {$len >= 0} {
    # regular output
    .log.tx configure -state normal
    .log.tx insert end "$l\n"
    .log.tx yview moveto 1
    if {$::tcl_platform(os) ne "Darwin"} {.log.tx configure -state disabled}
  }
}; # read_line_cb

# general gui utilities

# width of '0', as a rough estimate of average character width
# assume height == width*2
set ::cw [font measure TkTextFont "0"]

# unicode symbols as fake checkboxes in ttk::treeview widgets
proc mark_sym {mrk} {
  if $mrk {
    return "\u25A3" ; # 'white square containing black small square'
  } else {
    return "\u25A1" ; # 'white square'
  }
} ; # mark_sym

proc ppack {wdg args} { ; # pack command with padding
  pack $wdg {*}$args -padx 3 -pady 3
}

proc pgrid {wdg args} { ; # grid command with padding
  grid $wdg {*}$args -padx 3 -pady 3
}

# start new toplevel with settings appropriate for a dialog
proc create_dlg {wnd {p .}} {
  catch {destroy $wnd} ; # no error if it does not exist
  toplevel $wnd -class Dialog
  wm withdraw $wnd
  if [winfo viewable $p] {wm transient $wnd $p}
  if $::plain_unix {wm attributes $wnd -type dialog}
  wm protocol $wnd WM_DELETE_WINDOW {destroy $wnd}
}

# Place a dialog centered wrt its parent.
# If its geometry is somehow not yet available,
# its upperleft corner will be centered.

proc place_dlg {wnd {p "."}} {
  set g [wm geometry $p]
  scan $g "%dx%d+%d+%d" pw ph px py
  set hcenter [expr {$px + $pw / 2}]
  set vcenter [expr {$py + $ph / 2}]
  set g [wm geometry $wnd]
  set wh [winfo reqheight $wnd]
  set ww [winfo reqwidth $wnd]
  set wx [expr {$hcenter - $ww / 2}]
  if {$wx < 0} { set wx 0}
  set wy [expr {$vcenter - $wh / 2}]
  if {$wy < 0} { set wy 0}
  wm geometry $wnd [format "+%d+%d" $wx $wy]
  wm state $wnd normal
  raise $wnd $p
} ; # place_dlg

proc end_dlg {ans wnd {p "."}} {
  set ::dialog_ans $ans
  raise $p
  destroy $wnd
} ; # end_dlg

# ATM ::out_log will be shown only at the end
proc show_log {{do_abort 0}} {
  wm withdraw .
  foreach c [winfo children .] {
    destroy $c
  }

  # wallpaper
  pack [ttk::frame .bg] -fill both -expand 1

  pack [ttk::frame .log] -in .bg -fill both -expand 1
  pack [ttk::scrollbar .log.scroll -command ".log.tx yview"] \
      -side right -fill y
  ppack [text .log.tx -height 10 -wrap word -font TkDefaultFont \
      -yscrollcommand ".log.scroll set"] \
      -expand 1 -fill both
  .log.tx configure -state normal
  .log.tx delete 1.0 end
  foreach l $::out_log {
    .log.tx insert end "$l\n"
  }
  if {$::tcl_platform(os) ne "Darwin"} {.log.tx configure -state disabled}
  .log.tx yview moveto 1

  pack [ttk::frame .bottom] -in .bg -side bottom -fill x
  ttk::button .close -text "close" -command exit
  ppack .close -in .bottom -side right; # -anchor e
  if $do_abort {
    ttk::button .abort -text "abort" \
        -command {catch {chan close $::inst}; exit}
    ppack .abort -in .bottom -side right
  }

  set h [expr {40 * $::cw}]
  set w [expr {80 * $::cw}]
  wm geometry . "${w}x${h}"
  wm state . normal
}; # show_log

proc log_exit {{mess ""}} {
  if {$mess ne ""} {lappend ::out_log $mess}
  catch {chan close $::inst} ; # should terminate perl
  if {[llength $::out_log] > 0} {
    if {[llength $::out_log] < 10} {
      tk_messageBox -icon info -message [join $::out_log "\n"]
      exit
    } else {
      show_log ; # its close button exits
    }
  } else {
    exit
  }
}; # log_exit

proc make_splash {} {
  # picture and logo
  catch {
    image create photo tlimage -file \
        [file join $::instroot "tlpkg" "installer" "texlion.png"]
    pack [frame .white -background white] -fill x -expand 1
    label .image -image tlimage -background white
    pack .image -in .white
  }
  # wallpaper
  pack [ttk::frame .bg] -fill both -expand 1

  ppack [ttk::label .text -text "TeX Live 2018" -font bigfont] \
    -in .bg
  ppack [ttk::label .loading -text "Loading..."] -in .bg

  wm state . normal
  raise .
  update
}; # make_splash

# short descriptions for collections and schemes from texlive.tlpdb,
# not from the backend
proc get_short_descs {} {
  set dbfile [file join $::instroot "tlpkg/texlive.tlpdb"]
  set fid [open $dbfile r]
  # add some error checking
  chan configure $fid -translation auto
  set blob [read $fid]
  chan close $fid
  set lines [split $blob "\n"]
  set nm ""
  set shortdesc ""
  set category ""
  # make sure there is a terminator empty line for the last entry
  lappend lines ""
  set nm ""
  foreach l $lines {
    if {$l eq ""} {
      # end of entry
      if {$nm ne ""} {
        if {$category eq "Collection"} {
          set ::coll_descs($nm) $shortdesc
        } elseif {$category eq "Scheme"} {
          set ::scheme_descs($nm) $shortdesc
        }
      }
      set nm ""
      set category ""
      set shortdesc ""
    } elseif [string equal -length 5 "name " $l] {
      set nm [string range $l 5 end]
      if {$nm eq ""} {err_exit "Empty name in database"}
    } elseif {$nm eq ""} {
      err_exit "No database entry defined"
    } elseif [string equal -length 9 "category " $l] {
      set category [string range $l 9 end]
    } elseif [string equal -length 10 "shortdesc " $l] {
      set shortdesc [string range $l 10 end]
    } else {
      # disregard other database info
      continue
    }
  }
  set ::scheme_descs(scheme-custom) "Custom scheme"
}; # get_short_descs

#############################################################

# toggle platform in treeview widget, but not in underlying data
proc toggle_bin {b} {
  if {$b eq $::vars(this_platform)} {
    tk_messageBox -message "Cannot deselect own platform"
    return
  }
  set m [.tlbin.lst set $b "mk"]
  if {$m eq [mark_sym 0]} {
    .tlbin.lst set $b "mk" [mark_sym 1]
  } else {
    .tlbin.lst set $b "mk" [mark_sym 0]
  }
}; # toggle_bin

### binaries ###

proc save_bin_selections {} {
  set ::vars(n_systems_selected) 0
  foreach b [.tlbin.lst children {}] {
    set bb "binary_$b"
    if {[.tlbin.lst set $b "mk"] ne [mark_sym 0]} {
      incr ::vars(n_systems_selected)
      set ::vars($bb) 1
    } else {
      set ::vars($bb) 0
    }
    if {$b eq "win32"} {
      set ::vars(collection-wintools) $::vars($bb)
    }
  }
  update_vars
  if {$::vars(n_systems_selected) > 1} {
    .binlm configure -text \
        [format "%d additional platform(s)" \
             [expr {$::vars(n_systems_selected) - 1}]]
  } else {
    .binlm configure -text ""
  }
}; # save_bin_selections

proc select_binaries {} {
  create_dlg .tlbin .
  wm title .tlbin "Binaries"

  # wallpaper
  pack [ttk::frame .tlbin.bg] -expand 1 -fill both

  set max_width 0
  foreach b [array names ::bin_descs] {
    set bl [font measure TkTextFont $::bin_descs($b)]
    if {$bl > $max_width} {set max_width $bl}
  }
  incr max_width 10

  # treeview for binaries, with checkbox column and vertical scrollbar
  pack [ttk::frame .tlbin.binsf] -in .tlbin.bg -expand 1 -fill both

  ttk::treeview .tlbin.lst -columns {mk desc} -show {} \
      -height 15 -selectmode extended -yscrollcommand {.tlbin.binsc set}

  ttk::scrollbar .tlbin.binsc -orient vertical -command {.tlbin.lst yview}
  .tlbin.lst column mk -width [expr {$::cw * 3}]
  .tlbin.lst column desc -width $max_width
  foreach b [array names ::bin_descs] {
    set bb "binary_$b"
    .tlbin.lst insert {}  end -id $b -values \
        [list [mark_sym $::vars($bb)] $::bin_descs($b)]
  }
  ppack .tlbin.lst -in .tlbin.binsf -side left -expand 1 -fill both
  ppack .tlbin.binsc -in .tlbin.binsf -side right -expand 1 -fill y
  bind .tlbin.lst <space> {toggle_bin [.tlbin.lst focus]}
  bind .tlbin.lst <Return> {toggle_bin [.tlbin.lst focus]}
  bind .tlbin.lst <ButtonRelease-1> \
      {toggle_bin [.tlbin.lst identify item %x %y]}

  # ok, cancel buttons
  pack [ttk::frame .tlbin.buts] -in .tlbin.bg -expand 1 -fill x
  ttk::button .tlbin.ok -text "Ok" -command \
      {save_bin_selections; update_vars; end_dlg 1 .tlbin .}
  ppack .tlbin.ok -in .tlbin.buts -side right
  ttk::button .tlbin.cancel -text "Cancel" -command {end_dlg 0 .tlbin .}
  ppack .tlbin.cancel -in .tlbin.buts -side right

  place_dlg .tlbin .
  tkwait window .tlbin
  return $::dialog_ans
}; # select_binaries

#############################################################

### scheme ###
proc select_scheme {} {
  create_dlg .tlschm .
  wm title .tlschm "Schemes"

  # wallpaper
  pack [ttk::frame .tlschm.bg] -fill both -expand 1

  set max_width 0
  foreach s $::schemes_order {
    set sl [font measure TkTextFont $::scheme_descs($s)]
    if {$sl > $max_width} {set max_width $sl}
  }
  incr max_width 10
  ttk::treeview .tlschm.lst -columns {desc} -show {} -selectmode browse \
      -height [llength $::schemes_order]
  .tlschm.lst column "desc" -width $max_width -stretch 1
  ppack .tlschm.lst -in .tlschm.bg -fill x -expand 1
  foreach s $::schemes_order {
    .tlschm.lst insert {} end -id $s -values [list $::scheme_descs($s)]
  }
  # we already made sure that $::vars(selected_scheme) has a valid value
  .tlschm.lst selection set [list $::vars(selected_scheme)]
  pack [ttk::frame .tlschm.buts] -in .tlschm.bg -expand 1 -fill x
  ttk::button .tlschm.ok -text "Ok" -command {
    # tree selection is a list:
    set ::vars(selected_scheme) [lindex [.tlschm.lst selection] 0]
    foreach v [array names ::vars] {
      if {[string range $v 0 6] eq "scheme-"} {
        if {$v eq $::vars(selected_scheme)} {
          set ::vars($v) 1
        } else {
          set ::vars($v) 0
        }
      }
    }
    update_vars
    end_dlg 1 .tlschm .
  }
  ppack .tlschm.ok -in .tlschm.buts -side right
  ttk::button .tlschm.cancel -text "Cancel" -command {end_dlg 0 .tlschm .}
  ppack .tlschm.cancel -in .tlschm.buts -side right

  place_dlg .tlschm .
  tkwait window .tlschm
  return $::dialog_ans
}; # select_scheme

#############################################################

### collections ###

# toggle collection in treeview widget, but not in underlying data
proc toggle_coll {cs c} {
  # cs: treeview widget; c: selected child item
  set m [$cs set $c "mk"]
  if {$m eq [mark_sym 0]} {
    $cs set $c "mk" [mark_sym 1]
  } else {
    $cs set $c "mk" [mark_sym 0]
  }
}; # toggle_coll

proc save_coll_selections {} {
  foreach wgt {.tlcoll.other .tlcoll.lang} {
    foreach c [$wgt children {}] {
      if {[$wgt set $c "mk"] eq [mark_sym 0]} {
        set ::vars($c) 0
      } else {
        set ::vars($c) 1
      }
    }
  }
  set ::vars(selected_scheme) "scheme-custom"
  update_vars
}; # save_coll_selections

proc select_collections {} {
  # 2017: more than 40 collections
  # The tcl installer acquires collections from the database file,
  # but install-tl also has an array of collections.
  # Use treeview for checkbox column and collection descriptions
  # rather than names.
  # buttons: select all, select none, ok, cancel
  # should some collections be excluded? Check install-menu-* code.
  create_dlg .tlcoll .
  wm title .tlcoll "Collections"

  # wallpaper
  pack [ttk::frame .tlcoll.bg]

  # Treeview and scrollbar for non-language- and language collections resp.
  pack [ttk::frame .tlcoll.both] -in .tlcoll.bg -expand 1 -fill y

  set max_width 0
  foreach c [array names ::coll_descs] {
    set cl [font measure TkTextFont $::coll_descs($c)]
    if {$cl > $max_width} {set max_width $cl}
  }
  incr max_width 10
  foreach t {"lang" "other"} {
    set wgt ".tlcoll.$t"
    pack [ttk::frame ${wgt}f] \
        -in .tlcoll.both -side left -fill y

    ttk::treeview $wgt -columns {mk desc} -show {headings} \
        -height 20 -selectmode extended -yscrollcommand "${wgt}sc set"
    $wgt heading "mk" -text ""
    if {$t eq "lang"} {
      $wgt heading "desc" -text "Languages"
    } else {
      $wgt heading "desc" -text "Other collections"
    }

    ttk::scrollbar ${wgt}sc -orient vertical -command "$wgt yview"
    $wgt column mk -width [expr {$::cw * 3}]
    $wgt column desc -width $max_width
    ppack $wgt -in ${wgt}f -side left
    ppack ${wgt}sc -in ${wgt}f -side left -fill y

    bind $wgt <space> {toggle_coll %W [%W focus]}
    bind $wgt <Return> {toggle_coll %W [%W focus]}
    bind $wgt <ButtonRelease-1> {toggle_coll %W [%W identify item %x %y]}
  }

  foreach c [array names ::coll_descs] {
    if [string equal -length 15 "collection-lang" $c] {
      set wgt ".tlcoll.lang"
    } else {
      set wgt ".tlcoll.other"
    }
    $wgt insert {} end -id $c -values \
        [list [mark_sym $::vars($c)] $::coll_descs($c)]
  }

  # select none, select all, ok and cancel buttons
  pack [ttk::frame .tlcoll.butf] -fill x
  ttk::button .tlcoll.all \
      -text "Select all" \
      -command \
      {foreach wgt {.tlcoll.other .tlcoll.lang} {
        foreach c [$wgt children {}] {$wgt set $c "mk" [mark_sym 1]}
        }
      }
  ppack .tlcoll.all -in .tlcoll.butf -side left
  ttk::button .tlcoll.none \
      -text "Select none" \
      -command \
      {foreach wgt {.tlcoll.other .tlcoll.lang} {
        foreach c [$wgt children {}] {$wgt set $c "mk" [mark_sym 0]}
        }
      }
  ppack .tlcoll.none -in .tlcoll.butf -side left
  # the final two buttons close the menu toplevel
  ttk::button .tlcoll.ok -text "Ok" -command \
      {save_coll_selections; end_dlg 1 .tlcoll .}
  ppack .tlcoll.ok -in .tlcoll.butf -side right
  ttk::button .tlcoll.cancel -text "Cancel" -command {end_dlg 0 .tlcoll .}
  ppack .tlcoll.cancel -in .tlcoll.butf -side right

  place_dlg .tlcoll .
  wm resizable .tlcoll 0 0
  tkwait window .tlcoll
  return $::dialog_ans
}; # select_collections

#############################################################

# the main menu interface will at certain events send the current values of
# the ::vars array to install-tl[-tcl], which will send back an updated version
# of this array.
# We still use blocking i/o: frontend and backend wait for each other.

proc run_menu {} {
  wm withdraw .
  # destroy .splash
  foreach c [winfo children .] {
    destroy $c
  }

  # wallpaper and grid
  pack [ttk::frame .bg] -fill both -expand 1
  pack [ttk::frame .gridf] -in .bg -fill x -expand 1
  set rw -1

  # platforms
  incr rw
  pgrid [ttk::label .binl -text $::bin_descs($::vars(this_platform))] \
      -in .gridf -row $rw -column 0 -sticky w
  if {$::tcl_platform(platform) ne "windows"} {
    grid [ttk::frame .plf] -in .gridf -row $rw -column 1 -sticky ew
    ttk::button .binb -text "More platforms.." -command select_binaries
    ppack .binb -in .plf -side right
    ppack [ttk::label .binlm -text ""] -in .plf -side left
  }

  # schemes
  incr rw
  ttk::label .schml -textvariable ::vars(selected_scheme)
  pgrid .schml -in .gridf -row $rw -column 0 -sticky w
  ttk::button .schmb -text "Schemes" -command select_scheme
  pgrid .schmb -in .gridf -row $rw -column 1 -sticky e

  # collections
  incr rw
  grid [ttk::frame .collf] -in .gridf -row $rw -column 0 -sticky w
  ttk::label .ncolls -textvariable ::vars(n_collections_selected)
  ppack .ncolls -in .collf -side left
  ttk::label .lcoll -text \
      [format "out of %d collection(s)" $::vars(n_collections_available)]
  ppack .lcoll -in .collf -side left
  ttk::button .collb -text "Customize selection" -command select_collections
  pgrid .collb -in .gridf -row $rw -column 1 -sticky e

  # total size
  incr rw
  grid [ttk::frame .sizef] -in .gridf -row $rw -column 0
  ttk::label .lsize -text "Disk space required (in MB): "
  ppack .lsize -in .sizef -side left
  ttk::label .size_req -textvariable ::vars(total_size)
  ppack .size_req -in .sizef -side left


  # directory setup

  # options

  # required disk space
  incr rw

  # final buttons
  pack [ttk::frame .final] -in .bg -side bottom -fill x -expand 1
  ttk::button .install -text "Install" -command {
    set ::menu_ans "startinst"
  }
  ppack .install -in .final -side right
  ttk::button .quit -text "Quit" -command {
    set ::out_log {}
    set ::menu_ans "no_inst"
  }
  ppack .quit -in .final -side right

  wm state . normal
  unset -nocomplain ::menu_ans
  vwait ::menu_ans
  return $::menu_ans
}; # run_menu

#############################################################

# we need data from the backend.
# choices of schemes, platforms and options impact choices of
# collections and required disk space.
# the vars array contains all this variable information.
# the calc_depends proc communicates with the backend update this array.

proc read_vars {} {
  set l [read_line_no_eof]
  if {$l ne "vars"} {
    err_exit "'vars' expected but $l found"
  }
  while 1 {
    set l [read_line_no_eof]
    if [regexp {^([^:]+): (.*)$} $l m k v] {
      set ::vars($k) $v
    } elseif {$l eq "endvars"} {
      break
    } else {
      err_exit "Illegal line $l in vars section"
    }
  }
  if {"total_size" ni [array names ::vars]} {
    set ::vars(total_size) 0
  }
}; # read_vars

proc write_vars {} {
  chan puts $::inst "vars"
  foreach v [array names ::vars] {chan puts $::inst "$v: $::vars($v)"}
  chan puts $::inst "endvars"
  chan flush $::inst
}

proc update_vars {} {
  chan puts $::inst "calc"
  write_vars
  read_vars
}

proc read_menu_data {} {
  # the expected order is: vars, schemes (one line), binaries
  # note. lindex returns an empty string if the index argument is too high.
  # empty lines result in an err_exit.

  read_vars

  # schemes order (one line)
  set l [read_line_no_eof]
  if [regexp {^schemes_order: (.*)$} $l m sl] {
    set ::schemes_order $sl
  } else {
    err_exit "schemes_order expected but $l found"
  }
  if {"selected_scheme" ni [array names ::vars] || \
        $::vars(selected_scheme) ni $::schemes_order} {
    set ::vars(selected_scheme) [lindex $::schemes_order 0]
  }

  # binaries
  set l [read_line_no_eof]
  if {$l ne "binaries"} {
    err_exit "'binaries' expected but $l found"
  }
  while 1 {
    set l [read_line_no_eof]
    if [regexp {^([^:]+): (.*)$} $l m k v] {
      #if [info exists ::bin_descs($k)] {
      #  puts stderr "Duplicate key $k in binaries section"
      #}
      set ::bin_descs($k) $v
    } elseif {$l eq "endbinaries"} {
      break
    } else {
      err_exit "Illegal line $l in binaries section"
    }
  }

  set l [read_line_no_eof]
  if {$l ne "endmenudata"} {
    err_exit "'endmenudata' expected but $l found"
  }
}; # read_menu_data

proc answer_to_perl {} {
  # we just got a line "mess_yesno" from perl
  # finish reading the message text, put it in a message box
  # and write back the answer
  set mess {}
  while 1 {
    set ll [read_line]
    if {[lindex $ll 0] < 0} {
      err_exit "Error while reading from Perl backend"
    } else {
      set l [lindex $ll 1]
    }
    if  {$l eq "endmess"} {
      break
    } else {
      lappend mess $l
    }
  }
  set m [join $mess "\n"]
  set ans [tk_messageBox -type yesno -icon question -message $m]
  chan puts $::inst [expr {$ans eq yes ? "y" : "n"}]
  chan flush $::inst
}; # answer_to_perl

proc run_installer {} {
  set ::out_log {}
  show_log 1; # 1: with abort button
  .close configure -state disabled
  # startinst: does not makes sense for a profile installation
  if $::did_gui {
    chan puts $::inst "startinst"
    write_vars
  }

  # - non-blocking i/o
  chan configure $::inst -buffering line -blocking 0
  chan event $::inst readable read_line_cb
}; # run_installer

proc main_prog {} {

  # start install-tl-[tcl] via a pipe
  set cmd [list ${::perlbin} "${::instroot}/install-tl" \
               "-from_ext_gui" {*}$::argv]
  if [catch {open "|[join $cmd " "] 2>@1" r+} ::inst] {
    # "2>@1" ok under Windows >= XP
    err_exit "Error starting Perl backend"
  }
  set ::perlpid [pid $::inst]

  # scan tlpkg/TeXLive/TLConfig.pm for $ReleaseYear
  set ::release_year 0
  set cfg [open [file join $::instroot "tlpkg/TeXLive/TLConfig.pm"] r]
  set  re {\$ReleaseYear\s*=\s*([0-9]+)\s*;}
  while {[gets $cfg l] >= 0} {
    if [regexp $re $l m ::release_year] break
  }
  close $cfg

  wm title . "TeX Live $::release_year Installer"
  make_splash

  # do not start event-driven, non-blocking io
  # until the actual installation starts
  chan configure $::inst -buffering line -blocking 1

  # possible input from perl until the menu starts:
  # - question about prior canceled installation
  # - menu data, help, version, print-platform
  set ::did_gui 0
  set answer ""
  while 1 {
    set ll [read_line]
    if {[lindex $ll 0] < 0} break
    set l [lindex $ll 1]
    # There may be occasion for a dialog
    if {$l eq "mess_yesno"} {
      answer_to_perl
    } elseif {$l eq "menudata"} {
      # we do want a menu, so we expect menu data
      # this may take a while, so we put up a splash screen
      #make_splash
      read_menu_data
      get_short_descs ; # read short descriptions from TL package database
      set answer [run_menu]
      set ::did_gui 1
      break
    } elseif {$l eq "startinst"} {
      # use an existing profile:
      set ::out_log {}
      set answer "startinst"
      break
    } else {
      lappend ::out_log $l
    }
  }
  if {$answer eq "startinst"} {
    run_installer
    # invokes show_log which first destroys previous children
  } else {
    log_exit
  }
}

file delete $::dblfile

main_prog
