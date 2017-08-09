##
## plot_structure_stats.tcl
##
## Plots volumes of multiple subjects' brain structure volumes using
## existing statistics files.
##
## Original author: Kevin Teich
## CVS Revision Info:
##    $Author: nicks $
##    $Date: 2011/03/02 00:04:36 $
##    $Revision: 1.11 $
##
## Copyright © 2011 The General Hospital Corporation (Boston, MA) "MGH"
##
## Terms and conditions for use, reproduction, distribution and contribution
## are found in the 'FreeSurfer Software License Agreement' contained
## in the file 'LICENSE' found in the FreeSurfer distribution, and here:
##
## https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferSoftwareLicense
##
## Reporting: freesurfer@nmr.mgh.harvard.edu
##

if { $argc > 0 } {

  puts "
Usage: plot_structure_stats.tcl

Plots volumes of multiple subjects' brain structure volumes using
existing statistics files.

This script looks through your SUBJECTS_DIR and finds any *.stats
files generated by the FreeSurfer tool stream. These files
contain the volumes of brain structures found by the automatic
segmentation tools. plot_structure_stats.tcl then shows a window
in which you can select a structure. It will plot the different
volumes for each subject.

You can double click one of the data points to open up that subject
in tkmedit or tksurfer, depending on whether the structer is
volume or surface based.

plot_structure_stats.tcl will normally scan all subjects in your
SUBJECTS_DIR location. If you would like to specify a subset, list
the subjects in an environment variable named SUBJECTS, e.g.

setenv SUBJECTS \"subject1 subject2 subject3\"

"
  exit
}

package require Tix;
package require BLT;

# This function finds a file from a list of directories.
proc FindFile { ifnFile ilDirs } {
  foreach sPath $ilDirs {
    set sFullFileName [ file join $sPath $ifnFile ]
    if { [file readable $sFullFileName] } {
      puts "Reading $sFullFileName"
      return $sFullFileName
    }
  }
  puts "Couldn't find $ifnFile: Not in $ilDirs"
  return ""
}


# Also look for tkUtils.tcl.
set sDefaultScriptsDir ""
catch { set sDefaultScriptsDir "$env(FREESURFER_HOME)/lib/tcl" }
set sUtilsDir ""
catch { set sUtilsDir "$env(TKUTILS_SCRIPTS_DIR)" }

set fnUtils \
  [FindFile tkUtils.tcl \
     [list $sUtilsDir "." "../scripts" $sDefaultScriptsDir]]
if { [string compare $fnUtils ""] == 0 } { exit }
source $fnUtils

# gData
# lID - list of IDs
# $ID - id for this set of data
#   bInited - data is inited for this ID
#   lSubjects
#   lStructureSets
#   $structureSet,lStructures
#   $structureSet,$structure,$subject,size

# gPlot
# $ID - id for this plot
#   state
#   info  - current info string
#   sStructureSet - current structure set
#   nStructure - current structure index
#   hiElement - currently hilighted element
#   subjects
#     $nSubject - index into lSubjectDataLabels
#     visible  - whether to draw this subj in the graph
#     active  - whether to draw this subj in the graph

# constant values for stuff
set kValid(lMarkers) {square circle diamond plus cross splus scross triangle}
set kValid(lColors) {red blue green yellow black purple orange pink brown}

# For each subject in SUBJECTS_DIR, look for subject/stats/*.stats,
# and read each file.
proc PSS_ReadAllStatsInSubjectsDir { iID } {
  global env
  global gData gPlot

  if { ![info exists env(SUBJECTS_DIR)] } {
    puts "No SUBJECTS_DIR defined."
    exit
  }

  set gData($iID,bInited) false
  set gData($iID,lSubjects) {}
  set gData($iID,lStructureSets) {}

  set lSubjects [exec ls $env(SUBJECTS_DIR)]
  foreach sSubject $lSubjects {

    # If they have SUBJECTS set, look for this subject in that
    # list. If it's not found, continue.
    if { [info exists env(SUBJECTS)] } {
      if { [lsearch -exact $env(SUBJECTS) $sSubject] == -1 } {
        continue
      }
    }

    set lStats {}
    catch {
      set lFiles [exec ls [file join $env(SUBJECTS_DIR) $sSubject stats]]
      foreach fn $lFiles {
        if { [string match [file extension $fn] .stats] } {
          lappend lStats \
            [file join $env(SUBJECTS_DIR) $sSubject stats $fn]
        }
      }
    }

    # If we found any files, append this subject to our sujbects
    # list.
    if { [llength $lStats] > 0 } {
      lappend gData($iID,lSubjects) $sSubject
    }

    # For each file...
    foreach fnStat $lStats {

      # Now parse this file, adding the structure/values we find
      # to our data.
      PSS_ReadStatsFileIntoDataTable $iID $fnStat $sSubject

      # Start out visible and inactive.
      set gPlot($iID,state,subjects,$sSubject,visible) 1
      set gPlot($iID,state,subjects,$sSubject,active) 0
    }
  }

  set gData($iID,bInited) 1
}

#
#
# Read a .stats file. For each structure line, add the structure and
# size to our data table. Use the given subject label, or
# subject-{l,r}h if it's a surface stat file.
proc PSS_ReadStatsFileIntoDataTable { iID ifnStats isSubject } {
  global gData

  # Extract the structure set.
  set sStructureSet [file rootname [file tail $ifnStats]]

  # Add it to the list of structure sets.
  if { ![info exists gData($iID,lStructureSets)] ||
     [lsearch $gData($iID,lStructureSets) $sStructureSet] == -1 } {

    lappend gData($iID,lStructureSets) $sStructureSet
  }

  set gData($iID,$sStructureSet,lStructures) {}

  set fStats [open $ifnStats r]
  while { ![eof $fStats] } {
    set cRead [gets $fStats sLine]
    if { $cRead > 0 } {
      # If the first char is not a pound sign...
      if { ![string match [string range $sLine 0 1] \#] } {

        set sStructure none
        set volume 0
        set bGood 0

        # I'd like to do this with the * symbol to discard
        # fields, but it doesn't seem to work...
        # Volume .stats format
        set cScanned [scan $sLine "%d %d %d %e %s %e %e %e %e %e" \
                  a b c volume sStructure d e f g h]
        if { $cScanned == 10 } { set bGood 1 }

        # Surface .stats format
        if { !$bGood } {
          set cScanned [scan $sLine "%s %d %d %d %e %e %e %e %e %e" \
                    sStructure a area volume b c d e f g]
          if { $cScanned == 10 } { set bGood 1 }
        }

        # Still not good, skip this line.
        if { !$bGood } {
          continue
        }

        if { ![info exists gData($iID,$sStructureSet,lStructures)] ||
           [lsearch $gData($iID,$sStructureSet,lStructures) \
              $sStructure] == -1 } {
          lappend gData($iID,$sStructureSet,lStructures) $sStructure
        }

        set gData($iID,$sStructureSet,$sStructure,$isSubject,size) \
          $volume
      }
    }
  }
}

#
#
# Builds the main window. Assumes the header is already read.
proc PSS_BuildWindow { iID } {
  global gWidgets gData gPlot

  set wwTop     .pss-$iID
  set fwMenuBar   $wwTop.fwMenuBar
  set gwPlot      $wwTop.gwPlot
  set lwInfo      $wwTop.lwInfo
  set fwStructureSets $wwTop.fwStructureSets

  # Make sure we have data for this window.
  if { ![info exists gData($iID,bInited)] ||
     !$gData($iID,bInited) } {
    PSS_ReadAllStatsInSubjectsDir $iID
  }

  # Make the to window and set its title.
  toplevel $wwTop -height 500 -width 500
  wm title $wwTop "plot_structure_stats"

  # Make the menu bar.
  frame $fwMenuBar -border 2 -relief raised

  tkuMakeMenu -menu $fwMenuBar.mbwFile -label "File" -items {
    {command "New Window" { PSS_BuildWindow 1 }}
    {separator}
    {command "Quit:Alt Q" { PSS_Quit } }
  }

  pack $fwMenuBar.mbwFile -side left

  # Make the graph.
  blt::graph $gwPlot \
    -title "plot_structure_stats" \
    -plotbackground white \
    -relief raised -border 2

  # Bind our callbacks.
  $gwPlot legend bind all <Enter> [list PSS_CBLegendEnter $iID %W]
  $gwPlot legend bind all <Leave> [list PSS_CBLegendLeave $iID %W]
  $gwPlot legend bind all <ButtonPress-1> [list PSS_CBLegendClick $iID %W]
  bind $gwPlot <Motion> [list PSS_CBPlotMotion $iID %W %x %y]
  bind $gwPlot <Destroy> [list PSS_CBCloseWindow $iID]
  bind $gwPlot <Double-ButtonPress-1> [list PSS_CBPlotClick $iID %W %x %y]
  bind all <Alt-q> PSS_Quit

  # Set the y axis label.
  $gwPlot axis configure y -title "Volume"

  # Make the info label.
  set gPlot($iID,state,info) ""
  tkuMakeActiveLabel $lwInfo \
    -variable gPlot($iID,state,info)

  # Make the structure menus.
  frame $fwStructureSets
  foreach sStructureSet $gData($iID,lStructureSets) {

    set sWidget [regsub -all \\. $sStructureSet -]

    tkuMakeOptionMenu $fwStructureSets.ow-$sWidget \
      -command "PSS_SetStructure $iID $sStructureSet" \
      -label "$sStructureSet:" \
      -labelwidth 20 \
      -entries $gData($iID,$sStructureSet,lStructures)

    pack $fwStructureSets.ow-$sWidget \
      -side top -anchor w

    # Save this widget location.
    set gWidgets(menu,$sStructureSet) $fwStructureSets.ow-$sWidget
  }

  # Place everythingin the window.
  grid $fwMenuBar     -column 0 -row 0 -sticky new
  grid $gwPlot      -column 0 -row 1 -sticky news
  grid $lwInfo      -column 0 -row 2 -sticky nwe
  grid $fwStructureSets -column 0 -row 3 -sticky ws
  grid columnconfigure $wwTop 0 -weight 1
  grid rowconfigure $wwTop 0 -weight 0
  grid rowconfigure $wwTop 1 -weight 1
  grid rowconfigure $wwTop 2 -weight 0

  # Set the names in the gWidgets array.
  set gWidgets($iID,wwTop)       $wwTop
  set gWidgets($iID,gwPlot)      $gwPlot
  set gWidgets($iID,lwInfo)      $lwInfo
  set gWidgets($iID,fwStructureSets) $fwStructureSets

  # Create the pen for our active element.
  $gwPlot pen create activeElement \
    -symbol circle -color red -pixels 0.2i -fill ""

  # Note that the window has been built.
  set gWidgets($iID,bWindowBuilt) 1

  lappend gData(lID) $iID
}


#
#
# This plots the current data on the graph. It is fast enough that it
# can be called any time the data is changed to completely redraw it
# from scratch.
proc PSS_PlotData { iID } {
  global gWidgets gPlot gData

  # Don't plot if the window isn't built or we don't have data.
  if { ![info exists gWidgets($iID,bWindowBuilt)] ||
     ![info exists gData($iID,bInited)] ||
     !$gWidgets($iID,bWindowBuilt) ||
     !$gData($iID,bInited) } {
    return
  }

  set gw $gWidgets($iID,gwPlot)

  set sStructureSet $gPlot($iID,state,sStructureSet)
  set nStructure $gPlot($iID,state,nStructure)
  set sStructure [lindex $gData($iID,$sStructureSet,lStructures) $nStructure]

  # Set the x axis title to the label of the current structure.
  $gw axis configure x \
    -title [lindex $gData($iID,$sStructureSet,lStructures) \
          $gPlot($iID,state,nStructure)]

  # Remove all the elements and markers from the graph.
  set lElements [$gw element names *]
  foreach element $lElements {
    $gw element delete $element
  }
  set lMarkers [$gw marker names *]
  foreach marker $lMarkers {
    $gw marker delete $marker
  }

  set nSubject 0
  foreach sSubject $gData($iID,lSubjects) {

    if { [info exists \
          gData($iID,$sStructureSet,$sStructure,$sSubject,size)] } {

      # If this is visible, set the hide flag off and the color to
      # blue. Otherwise set the hide flag on and color to white. It
      # will draw white in the legend.
      if { $gPlot($iID,state,subjects,$sSubject,visible) } {
        set bHide 0

        if { $gPlot($iID,state,subjects,$sSubject,active) } {
          set color red
        } else {
          set color blue
        }

      } else {
        set bHide 1
        set color white
      }

      $gw element create $sSubject \
        -data [list $nSubject \
               $gData($iID, \
                    $sStructureSet, \
                    $sStructure, \
                    $sSubject,size)] \
        -linewidth 0 -outlinewidth 1 \
        -hide $bHide -color $color \
        -activepen activeElement

      incr nSubject
    }
  }
}

#
#
# Our callbacks.
proc PSS_CBCloseWindow { iID } {
  global gWidgets
  set gWidgets($iID,bWindowBuilt) 0
}


#
#
# When mouse goes in the legend, we get the current element in the
# legend and highlight that element in the graph.
proc PSS_CBLegendEnter { iID igw } {
  PSS_HilightElement $iID [$igw legend get current]
}

#
#
# Same but now we unhighlight it.
proc PSS_CBLegendLeave { iID igw } {
  PSS_UnhilightElement $iID [$igw legend get current]
}

#
#
# When you click an item in the legend, toggle the visibility in the
# graph.
proc PSS_CBLegendClick { iID igw } {
  PSS_ToggleVisibility $iID [$igw legend get current]
  PSS_PlotData $iID
}

#
#
# When the mouse is in the graph, if we mouse over an element, focus
# on that element.
proc PSS_CBPlotMotion { iID igw iX iY } {
  PSS_UnfocusElement $iID
  set lResult [PSS_FindMousedElement $iID $iX $iY]
  set element [lindex $lResult 0]
  if { "$element" != "" } {
    set index [lindex $lResult 1]
    set x [lindex $lResult 2]
    set y [lindex $lResult 3]
    PSS_FocusElement $iID $element $index $x $y
  }
}

#
#
# When you click an item in the graph, open it in tkmedit or tksurfer.
proc PSS_CBPlotClick { iID igw iX iY } {
  global gData gPlot env

  set lResult [PSS_FindMousedElement $iID $iX $iY]
  set element [lindex $lResult 0]
  if { "$element" != "" } {

    # The element is the subject name.
    set sSubject $element

    # Figure out if we should open this as a surface with a
    # parcellation or a volume with a segmentation. Note that the
    # structure set _should_ be the same as the name of the aseg
    # volume or parcellation if we append .mgz or .annot to it.

    set sStructureSet $gPlot($iID,state,sStructureSet)

    # First check if there is a .mgz or .mgh file with the same name.
    if { [file exists [file join $env(SUBJECTS_DIR) $sSubject mri $sStructureSet.mgz]] || 
       [file exists [file join $env(SUBJECTS_DIR) $sSubject mri $sStructureSet.mgh]]} {

      # The seg volume name is the structure set with .mgz or
      # .mgh appended.
      if { [file exists [file join $env(SUBJECTS_DIR) $sSubject mri $sStructureSet.mgz]] } {
        set sSegVolume $sStructureSet.mgz
      } else {
        set sSegVolume $sStructureSet.mgh
      }

      # Look for T1.{mgz,mgh} and orig.{mgz.mgh} for anatomical volumes.
      set sAnatVolume ""
      foreach sTestAnatVolume {T1.mgz T1.mgh orig.mgz orig.mgh} {
        if { [file exists [file join $env(SUBJECTS_DIR) $sSubject mri $sTestAnatVolume]] } {
          set sAnatVolume $sTestAnatVolume
          break
        }
      }
      if { [string match $sAnatVolume ""] } {
        puts "Coulnd't find anatomical volume for $sSubject"
        return
      }

      # Look for norm.{mgz,mgh} for the aux volume.
      set sAuxVolume ""
      foreach sTestAuxVolume {norm.mgz norm.mgh} {
        if { [file exists [file join $env(SUBJECTS_DIR) $sSubject mri $sTestAuxVolume]] } {
          set sAuxVolume $sTestAuxVolume
          break
        }
      }

      # Call tkmedit.
      if { [string match $sAuxVolume ""] } {
        PSS_RunViewerCmd $iID $sSubject \
          "tkmedit $sSubject $sAnatVolume -segmentation $sSegVolume"
      } else {
        PSS_RunViewerCmd $iID $sSubject \
          "tkmedit $sSubject $sAnatVolume -aux $sAuxVolume -segmentation $sSegVolume"
      }

    } elseif { [file exists [file join $env(SUBJECTS_DIR) $sSubject label $sStructureSet.annot]] } {

      # We need a hemi and a surface to load up the
      # parcellation. Scan the structure set for lh or rh for
      # the hemi, and then use it to look for surfaces.
      set sHemi ""
      if { [string match [string range $sStructureSet 0 1] lh] } {
        set sHemi lh
      } elseif { [string match [string range $sStructureSet 0 1] rh] } {
        set sHemi rh
      }
      if { [string match $sHemi ""] } {
        puts "Couldn't find a hemi in the structure set."
        return
      }

      # Look for the inflated surface.
      set sSurface ""
      if { [file exists [file join $env(SUBJECTS_DIR) $sSubject surf $sHemi.inflated]] } {
        set sSurface inflated
      }
      if { [string match $sSurface ""] } {
        puts "Couldn't find inflated surface."
        return
      }

      # Call tksurfer
      PSS_RunViewerCmd $iID $sSubject "tksurfer $sSubject $sHemi $sSurface -annotation [file join $env(SUBJECTS_DIR) $sSubject label $sStructureSet.annot]"

    } else {
      puts "Cannot find a seg volume or annot file to load."
    }
  }
}


#
#
# Hilight/UnhilightElement selects/unselects the element name in the
# legend and change the drawing pen of the element in the graph, which
# if activated draws it with a red circle around it.
proc PSS_HilightElement { iID iElement } {
  global gWidgets
  $gWidgets($iID,gwPlot) legend activate $iElement
  $gWidgets($iID,gwPlot) element activate $iElement
}

proc PSS_UnhilightElement { iID iElement } {
  global gWidgets
  $gWidgets($iID,gwPlot) legend deactivate $iElement
  $gWidgets($iID,gwPlot) element deactivate $iElement
}


#
#
# Shows or hide an element by name. Changes the value of the gPlot
# visibility flag.
proc PSS_ToggleVisibility { iID iElement } {
  global gPlot

  if { $gPlot($iID,state,subjects,$iElement,visible) } {
    set gPlot($iID,state,subjects,$iElement,visible) 0
  } else {
    set gPlot($iID,state,subjects,$iElement,visible) 1
  }
}


#
#
# Focus/Unfocus is called to 'mouseover' an element. It
# Hilight/Unhilights an element and puts or removes the subject name
# in a text marker in the graph.
proc PSS_UnfocusElement { iID } {
  global gPlot gWidgets

  # If we have a focused element, unhighlight it, set the
  # highlighted element name to null, and delete the hover text
  # marker.
  if { [info exists gPlot($iID,state,hiElement)] && \
       "$gPlot($iID,state,hiElement)" != "" } {
    PSS_UnhilightElement $iID $gPlot($iID,state,hiElement)
    set gPlot($iID,state,hiElement) ""
    $gWidgets($iID,gwPlot) marker delete hover
  }
}

proc PSS_FocusElement { iID iElement inSubjInClass iX iY } {
  global gPlot gWidgets gGDF

  # Set the highlighted element name and highlight the element.
  set gPlot($iID,state,hiElement) $iElement
  PSS_HilightElement $iID $gPlot($iID,state,hiElement)

  set sId $iElement

  $gWidgets($iID,gwPlot) marker create text \
    -name hover -text $sId -anchor nw \
    -coords [list $iX $iY]
}


#
#
# Finds the element under the mouse.
proc PSS_FindMousedElement { iID iX iY } {
  global gWidgets
  set bFound [$gWidgets($iID,gwPlot) element closest $iX $iY aFound -halo 10]
  if { $bFound } {
    return [list $aFound(name) $aFound(index) $aFound(x) $aFound(y)]
  }
  return ""
}

proc PSS_RunViewerCmd { iID isSubject isCommand } {
  global gPlot

  set gPlot($iID,state,subjects,$isSubject,active) 1
  PSS_PlotData $iID

  set fCmd [open "|$isCommand" r]
  set commandPID [pid $fCmd]

  fconfigure $fCmd -buffering line -blocking 0

  fileevent $fCmd readable \
    "PSS_PrintLog $iID $isSubject $fCmd $commandPID"

}

proc PSS_PrintLog { iID isSubject ifCmd iCmdPID } {
  global gPlot

  if { [eof $ifCmd] } {

    close $ifCmd

    set gPlot($iID,state,subjects,$isSubject,active) 0
    PSS_PlotData $iID

  } else {

    gets $ifCmd line
    puts "$isSubject: $line"
    update idletasks
  }
}

proc PSS_Quit {} {
  exit
}

# ============================================================ PUBLIC


#
#
# Call once before anything else to initialize the data structures.
proc PSS_Init {} {
  global gWidgets gData
  set gData(lID) {}
}


#
#
# Show or hide the window. If it hasn't been built, builds the window
# first.
proc PSS_ShowWindow { iID } {
  global gData gWidgets
  if { ![info exists gWidgets($iID,bWindowBuilt)] ||
     !$gWidgets($iID,bWindowBuilt) } {
    PSS_BuildWindow $iID
  }
  if { [lsearch $gData(lID) $iID] == -1 } { puts "ID not found"; return }
  wm deiconify $gWidgets($iID,wwTop)
  if { [info exists gWidgets($iID,state,window,geometry)] } {
    wm geometry $gWidgets($iID,wwTop) $gWidgets($iID,state,window,geometry)
  }
}

proc PSS_HideWindow { iID } {
  global gData gWidgets
  if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
  if { [info exists gWidgets($iID,wwTop)] } {
    set gWidgets($iID,state,window,geometry) \
      [wm geometry $gWidgets($iID,wwTop)]
    wm withdraw $gWidgets($iID,wwTop)
  }
}


#
#
# Set the current structure.
proc PSS_SetStructure { iID isStructureSet inStructure } {
  global gWidgets gPlot gData
  if { [lsearch $gData(lID) $iID] == -1 } { puts "ID not found"; return }

  # Clear the text in the current menu.
  catch {
    tkuSetOptionMenuText $gWidgets(menu,$gPlot($iID,state,sStructureSet))
  }

  # Save the new currents.
  set gPlot($iID,state,sStructureSet) $isStructureSet
  set gPlot($iID,state,nStructure) $inStructure

  PSS_PlotData $iID
}


#
#
# Set the info string displayed under the graph.
proc PSS_SetInfo { iID isInfo } {
  global gData gPlot
  if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
  set gPlot($iID,state,info) $isInfo
}


#
#
# Save the currently plotted data to a table.
proc PSS_SaveToTable { iID ifnTable } {
  global gPlot gGDF gbLibLoaded
  if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }

  set fp 0
  set err [catch {set fp [open $ifnTable w+]}]
  if { $err || $fp == 0 } {
    puts "Couldn't write file $ifnTable."
    return
  }

  puts $fp "Graph: $gGDF($iID,title)"
  puts $fp "Data: $gGDF($iID,dataFileName)"
  puts $fp "Variable: $gGDF($iID,variables,$gPlot($iID,state,nVariable),label)"
  puts $fp "Measurement: $gGDF($iID,measurementName)"
  puts $fp "subject id, class id, variable value, measurement value, standard deviation"
  puts $fp "------------"
  for { set nSubj 0 } { $nSubj < $gGDF($iID,cSubjects) } { incr nSubj } {

    set subjLabel $gGDF($iID,subjects,$nSubj,id)
    set classLabel $gGDF($iID,classes,$gGDF($iID,subjects,$nSubj,nClass),label)
    set var $gPlot($iID,state,data,subjects,$nSubj,variable)
    set meas $gPlot($iID,state,data,subjects,$nSubj,measurement)
    set stdDev $gPlot($iID,state,data,subjects,$nSubj,stdDev)

    puts $fp "$subjLabel $classLabel $var $meas $stdDev"
  }
  puts $fp "------------"
  puts ""

  close $fp
}


#
#
# Save the current plot graphic to a postscript file.
proc PSS_SaveToPostscript { iID ifnPS } {
  global gGDF gWidgets gbLibLoaded
  if { !$gbLibLoaded } { return }
  if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
  set err [catch {$gWidgets($iID,gwPlot) postscript output $ifnPS} sResult]
  if { $err } {
    puts "Could not save postscript file: $sResult"
  }
}


PSS_Init
PSS_ReadAllStatsInSubjectsDir 0
PSS_ShowWindow 0

wm withdraw .