#!/bin/sh
VERSION="0.7"
#XDIALOG="dialog"
#ZENITY="zenity"
VIEWER_OPTIONS="-shared -fullscreen -passwd ${HOME}/.vnc/passwd"

# Zenity dialog size (divisor of screen)
ZWIDTH=2
ZHEIGHT=2

# Window server information - detect by default
width=`xwininfo -root | grep Width: | cut -d: -f2 | tr -d " \t"`
height=`xwininfo -root | grep Height: | cut -d: -f2 | tr -d " \t"`
depth=`xwininfo -root | grep Depth: | cut -d: -f2 | tr -d " \t"`

ZOPTIONS=""
[ $ZWIDTH ] && ZOPTIONS="$ZOPTIONS --width=$(($width/$ZWIDTH))"
[ $ZHEIGHT ] && ZOPTIONS="$ZOPTIONS --height=$(($height/$ZHEIGHT))"

testexist ()
{    
    for program in "$1"; do
    	which $program > /dev/null && echo $1 && exit 0
    done
}

newscreen ()
{
    dhost=`echo $DISPLAY | cut -d: -f1`

    export SVNCWIDTH=$width
    export SVNCHEIGHT=$height
    export SVNCHOST=$dhost
    [ $DEBUG ] && echo "$SVNCWIDTH x $SVNCHEIGHT @ $SVNCHOST"

    VNCDISPLAY=`vncserver -depth $depth -geometry ${width}x${height} -name "${USER}-${dhost} (${width}x${height})"  2>&1 | grep ^New | cut -d: -f2` 

    [ $DEBUG ] && echo "VNCDISPLAY = $VNCDISPLAY (if null, bad)"
    $VIEW localhost:$VNCDISPLAY || exit 1
}

getname ()
{
    NAME=`$PS | grep "[X]vnc.*:$1 " | sed \
    "s/.*Xvnc.*:"$1".*-desktop\(.*\)-auth.*/\1/;" | tr -d "\t\n "`
    echo $NAME |tr -s "/ /" "/ /"
}

getmenus ()
{
    for vncdisplay in `$PS | grep [X]vnc | cut -d: -f$PSFIELD | tr -s "/ /" "/\t/" | cut -f1`; do
    	if [ $XDIALOG ]; then
    	 	echo -n "$vncdisplay \""`getname $vncdisplay | tr -d "\t\n\r"`"\" "
        elif [ $ZENITY ]; then
    	 	echo -n "$vncdisplay ${vncdisplay}_'`getname $vncdisplay | tr -d "\t\n\r"`' "
        else
    	 	echo -n "$vncdisplay:"$(($vncdisplay+100))","
    	fi
    done
}

[ -z $XDIALOG ] && XDIALOG=`testexist Xdialog xdialog`
[ -z "$XDIALOG" ] && unset XDIALOG
[ -z $ZENITY ] && ZENITY=`testexist zenity`
[ -z "$ZENITY" ] && unset ZENITY
# If all else fails, fallback is to xmessage - yuck!

if ( echo "$@" | grep -- "-D" > /dev/null ) ; then DEBUG=1; fi
if ( echo "$@" | grep -- "-xc" > /dev/null ) ; then unset XDIALOG && unset ZENITY; fi
if ( echo "$@" | grep -- "-h" > /dev/null ) ; then 
    echo "X Multisession/VNC Menu, Version: $VERSION"
    echo ""
    echo "Usage: $0 [-D] [-h]"
    echo "-D  enable debug"
    echo "-h  show help"
    echo "-xc use xconsole (fallback)"
    exit 0
fi

PSFIELD="2" # should be same across platforms, assuming ps options are right.

VNCVIEWER=`testexist vncviewer xvncviewer`
if [ -z "$VNCVIEWER" ]; then
    echo "No vncviewer found. Exiting."
    exit 1
fi

case `uname -s` in
    IRIX*)
    	PS="ps -x -u $USER -o comm"
    ;;
    *BSD)
    	PS="ps -x -o command"
    ;;
    Linux)
    	PS="ps -u $USER xo command"
    ;;
    *)
    	echo "OS not supported"
    	exit 0
    ;;
esac

[ $DEBUG ] && echo -e "PS: $PS\nVNCVIEWER: $VNCVIEWER"
    
VIEW="$VNCVIEWER $VIEWER_OPTIONS"

MENUS=`getmenus $USER`
[ $DEBUG ] && echo "MENU: $MENUS"

if [ -n "$XDIALOG" ]; then
    ANSWER=$($XDIALOG --cancel-label="Logout" --menubox "Which desktop do you wish to load?" 20 80 50 $MENUS N "Start a new resident session" F "Start a new local session (faster)" L "Lock the screen" K "Kill all sessions" 2>&1)
elif [ -n "$ZENITY" ]; then
    ANSWER=$($ZENITY $ZOPTIONS --list --radiolist --print-column 1 --column "" --column Description  $MENUS N "Start a new resident session" F "Start a new local session (faster)" L "Lock the screen" K "Kill all sessions" 2>&1)
else
    ANSWER=$(xmessage -buttons $MENUS"Start a new resident session":97,"Start non-resident session":98,"Lock screen":99,"Kill all sessions":100 "Which desktop do you wish to load?" 2>&1)
fi

exitstat=$?
if [ $exitstat -gt 100 ]; then 
    $VIEW localhost:$(($exitstat - 100)) || exit 1
elif [ $exitstat -eq 1 ] || [ -z $ANSWER ]; then
    exit 1;
else
    ([ $ZENITY ] || [ $XDIALOG ]) && VNCDISPLAY=$(echo -e "$ANSWER" | tail -n1) || VNCDISPLAY="$exitstat"

    case "$VNCDISPLAY" in
    	N|97|'Start a new resident session')
    		newscreen
    	;;
    	L|99|'Lock the screen')
    		xscreensaver-command -lock
    	;;
    	K|100|'Kill all sessions')
    		# more portable then killall
    		killcmd="for pid in `pidof Xvnc`; do kill -9 $pid; done"

    		if [ $XDIALOG ]; then
    			$XDIALOG --title "WARNING" --yesno "Are you sure you want to do this?"  10 80 && $killcmd 
            elif [ $ZENITY ]; then
                $ZENITY --title "WARNING" --question && $killcmd
    		else 
    			xmessage -buttons "Yes":2,"No":3
    			[ $? -eq 2 ] && $killcmd
    		fi
    		# relaunch the menu
    		$0
    		exit 0
    	;;
    	F|98|'Start non-resident session')
    		if [ -x ~/.vnc/xstartup ]; then
    			~/.vnc/xstartup
    		elif [ -f ~/.vnc/xstartup ]; then
    			/bin/sh ~/.vnc/xstartup
    		else 
    			xterm
    		fi
    	;;
    	*)
            [ "$ZENITY" ] && VNCDISPLAY=`echo $VNCDISPLAY | sed 's/^\(..\)_.*/\1/;'`
    		[ -z "$XDIALOG" ] && [ -z "$ZENITY" ] && VNCDISPLAY=$(($VNCDISPLAY-100))
    		$VIEW localhost:$VNCDISPLAY || exit 1
    	;;
    esac
fi

