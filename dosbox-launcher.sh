#!/usr/bin/env bash

dosboxromdir="${HOME}/ARES/roms/pc/gog"
game=$(basename -s .sh "${0}")

# DOSBox settings override
export DOSBOX_SDL_USESCANCODES=false
export LC_ALL="C"

if [[ -x "/opt/ares/emulators/dosbox/bin/dosbox" ]]; then
	emu="/opt/ares/emulators/dosbox/bin/dosbox"
fi

if ! [[ -x "$(command -v ${emu:-dosbox})" ]]; then
        echo 'DOSBox not found but is required for most GOG software.  Try installing the optional package "dosbox" from the ARES Setup script.'
	exit 1
fi

if [[ -d "${dosboxromdir}/${game}/DOSBOX" ]]; then
	workdir="${dosboxromdir}/${game}/DOSBOX"
	cd "${workdir}" || exit 1

	#Fixes
	
	# stargunner on Linux fix: 
	if [[ -f "../dosboxSTARGUN_single.conf" ]] && ! grep -q "pause" ../dosboxSTARGUN_single.conf; then
		#This fixes stargunner from crashing on load on linux
		ed -s ../dosboxSTARGUN_single.conf <<<$'g/STARGUN\\.exe/i\\\npause\nw'
	fi

	IFS=" " read -r -a dosboxargs < <(jq --raw-output '.playTasks[] | select(.isPrimary==true) | .arguments' ../goggame-*.info | sed 's:\\:/:g;s:\"::g')

	# If case there is no json file with the launch command, we guess the launch command
	if [[ -z "${dosboxargs[*]}" ]]; then
		dosboxargs=(
			-conf
			"$(find .. -maxdepth 1 -name 'dosbox*.conf' | awk '{print length " " $1}' | sort -n | head -1 | awk '{print $2}')"
			-conf
			"$(find .. -maxdepth 1 -name 'dosbox*single.conf' | head -1)"
			-c
			exit
		)

	fi

elif [[ -d "${dosboxromdir}/${game}/dosbox" ]]; then
	workdir="${dosboxromdir}/${game}"
	cd "${workdir}" || exit 1

	dosboxargs=(
		-conf
		"$(find . -maxdepth 1 -name 'dosbox*.conf' | awk '{print length " " $1}' | sort -n | head -1 | awk '{print $2}')"
		-conf
		"$(find . -maxdepth 1 -name 'dosbox*single.conf' | head -1)"
		-c
		exit
	)

else
	exit 1
fi

echo "Found arugments: ${dosboxargs[*]}"
echo "Launching ${game}"

"${emu:-dosbox}" "${dosboxargs[@]}"
