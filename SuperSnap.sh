#===================VARIABLES===================#
servicename=SuperSnap
    version=3.5
saved_folder="/sdcard/$servicename"
#known_database="$saved_folder/processedfiles.db" #old, no longer used
temp_file_read="$saved_folder/temp.txt"
dir1="/data/data/com.snapchat.android/files/file_manager/media"
dir2="/data/data/com.snapchat.android/files/file_manager/chat_snap"
dir3="/data/data/com.snapchat.android/files/file_manager/story_snap"
inject_file="$saved_folder/inject"
old_injections="$saved_folder/old_injections"
ffmpeg_bin="/data/data/com.termux/files/usr/bin/./ffmpeg"
convert_bin="/data/data/com.termux/files/usr/bin/./convert"
#===================VARIABLES===================#

#================Create folders=================#
mkdir $saved_folder          >/dev/null 2>&1
mkdir $saved_folder/Sent/    >/dev/null 2>&1
mkdir $saved_folder/Snaps/   >/dev/null 2>&1
mkdir $saved_folder/Stories/ >/dev/null 2>&1
mkdir $old_injections		 >/dev/null 2>&1
#================Create folders=================#
rm -rf $dir1/* $dir2/* $dir3/*
script_name=$saved_folder.sh

pidold=$(cat /sdcard/SS_pid)
kill -9 $pidold
echo $$ > /sdcard/SS_pid

setdate (){
dt=$(date +%Y-%m-%d_%H-%M-%S) #get datestamp
}
log (){
setdate
text="[$dt] $1"
echo $text  >> $saved_folder/$servicename.log
echo $text
}
log "$servicename $version initialized"
supersnap (){
for file in $(find $dir1 $dir2 $dir3 -name '*_snap.*' -o -name '*media.*')
do
	if [[ $file == *"tmp"* ]]; then return; fi #make sure it's not a temp/tmp file, such as a saved snap video that is still being recorded
	curdate=`date +%s`	#get the current date
	filedate=`stat -c %Y $file` #get the file's date
	age=`expr $curdate - $filedate` #get the file's age
	if [[ $age -gt "10800" ]]; then rm -rf $file && log "Deleted old file: $file" && return; fi #see if file is older than three hours and delete it if it is
	FILESIZE=$(stat -c%s "$file") #get the current file's size
	if [[ $FILESIZE -gt "50" ]]; #make sure file is not a very small ini file. this is not a failsafe and the script doesfurther testing to make 
	then					     #sure the file is valid and should be saved, but will elliminate the possibility of any very small files being saved
		id=${file##*/}   	 #get init id		
		idt="${id: -1}"  		 #get id trailer
		idm=${id%%.*}    		 #get main id
		idmabv=${idm::8}          #*, abv
		idfinal=${idm}.${idt}	 #finalize id
		idfinalabv=${idmabv}.${idt}   #*, abv
		setdate
		#dynamic variables for storing datetime information based on snap ID
		id2date=`eval echo date_${idmabv}`
		id2val=$(eval echo \${$id2date})
		if [ ! -z $id2val ]; then
			dt=$id2val          #if dynamic variable exists, set the datetime stamp of the next saved file (excluding "sent") to that date
		else 
			eval $id2date=$dt   #if it does NOT exist, set its value as the current datetime
		fi
		ext="dontkeep"														#default extension. This won't be changed if it's not a valid or necessary file
		head -c 50 $file   > 			    $temp_file_read                 #dump the first 50 bytes of the current snap to a temporary file
		if grep -q "PK"      			    $temp_file_read; then ext="zip"; fi			    #zip file containing main media and overlay
		if grep -q "ftyp"     			    $temp_file_read; then ext="mp4"; fi 			#mp4 video file
		if grep -q "JFIF"                   $temp_file_read; then ext="jpg"; fi			    #jpg image file
		if grep -q -e "PNG"  -e "RIFF"      $temp_file_read; then ext="overlay.png"; fi 	#png image file, which is always an overlay
		#determine type of media (sent snap, received snap, or story)
		if [[ $file == *"media."* ]]; then   mediatype="Sent";    fi
		if [[ $file == *"chat_snap."* ]]; then   mediatype="Snaps";    fi
		if [[ $file == *"story_snap."* ]]; then   mediatype="Stories";    fi
		#camera feed injection
		if [ $mediatype == "Sent" ];
		then
			setdate #reset the datestamp no matter if the media will be injected with another video/image, since sent videos will never have matching dates
			if [[ $ext == "mp4" ]] || [[ $ext == "jpg" ]] && [[ -f "${inject_file}.${ext}" ]]; #inject if the inject file exists, and
			then #it matches the current media type (mp4 or jpg)
				if [ $ext == "mp4" ]
				then
					#ffmeg command for videos
					$ffmpeg_bin -i ${inject_file}.${ext} -vf "transpose=2" -vcodec libx264 -acodec aac ${inject_file}_converted.${ext} > /sdcard/SuperSnap/temp_mp4.txt  # rotate 270 degrees
					sleep .5
					rm -f ${inject_file}.${ext}
					sleep .5
					mv ${inject_file}_converted.${ext} ${inject_file}.${ext}
					sleep .5
					
				elif [ $ext == "jpg" ]
				then
					#convert command for photos
					$convert_bin ${inject_file}.${ext} -rotate 270 ${inject_file}_converted.${ext} > /sdcard/SuperSnap/temp_jpg.txt # rotate 270 degrees
					sleep .5
					rm -f ${inject_file}.${ext}
					sleep .5
					mv ${inject_file}_converted.${ext} ${inject_file}.${ext}
					sleep .5
				fi
				rm -f $file	#remove the current snap in preparation for injection
				sleep .5 #wait a half second (safety feature)
				cp ${inject_file}.${ext} $file #inject the file
				chmod 777 $file #full permissions
				log "Injected media with \"${inject_file}.${ext}\"" #just log the information
				mv ${inject_file}.${ext} ${inject_file}.${ext}.bak
				#mv ${inject_file}.${ext} $old_injections/old_inject_${dt}.$ext #keep the old injection for future use/reference, but move it to another folder
			fi
		fi
		if [ ! -f "$saved_folder/.disable_$mediatype" ]; then #test to see if saving this type of media is disabled
			if [ $ext != "dontkeep" ]; then #save only if valid media is detected, aka the file no longer has "dontkeep" extension
				fname=${dt}_${idfinalabv}_${mediatype}.${ext} #naming scheme, can be changed here without hurting script as long as ${idfinalabv} still exists in name
				fpath=$saved_folder/$mediatype/$fname
				cd $saved_folder/$mediatype
				if [ ! -f *"$idfinalabv"* ]; then
					cp $file $fpath
					log "Saved new media: $fpath"
					echo 110 > /sys/class/timed_output/vibrator/enable  >/dev/null 2>&1
					#monkey -p com.vibrate 1 >/dev/null 2>&1
					echo 1 >/sys/class/leds/vibrator/activate  >/dev/null 2>&1
				fi
			fi
		else
			log "Refused to save ${id}: \"$mediatype\" saving is disabled" #tell the user that saving was refused because the .disable_<snaptype> file exists
		fi
	fi
done
}
while :
do
	supersnap
done
