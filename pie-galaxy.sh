#!/usr/bin/env bash
# This application was made by https://github.com/sigboe
# The License is GNU General Public License v3.0
# https://github.com/sigboe/pie-galaxy/blob/master/LICENSE
# shellcheck disable=SC2094 # Dirty hack avoid runcommand to steal stdout

#Default settings don't edit as they will be overwritten when you update the program
#set prefrences in ~/.config/piegalaxy/piegalaxy.conf
shopt -s extglob
title="Pie Galaxy"
tmpdir="${HOME}/.cache/piegalaxy"
downdir="${HOME}/Downloads"
romdir="${HOME}/ARES/roms"
dosboxdir="${romdir}/pc/gog"
scummvmdir="${romdir}/scummvm"
biosdir="${HOME}/ARES/BIOS"
scriptdir="$(dirname "$(readlink -f "${0}")")"
wyvernbin="${scriptdir}/wyvern"
innobin="${scriptdir}/innoextract"
imgViewer=(fbi -1 -t 5 -noverbose -a) #fbi -a -1 -t 5 #"${scriptdir}/pixterm" -d 1 -s 1
exceptions="${scriptdir}/exceptions"
renderhtml=(html2text -width 999 -style pretty)
areshelper="${HOME}/ARES-Setup/scriptmodules/helpers.sh"
configfile="${HOME}/.config/piegalaxy/piegalaxy.conf"
fullFileBrowser="false"
showImage="true"
version="0.4"

# fix UTF-8 symbols like © or ™
export LC_ALL=C.UTF-8
export LANGUAGE=C.UTF-8

if [[ -n "${XDG_CACHE_HOME}" ]]; then
	tmpdir="${XDG_CACHE_HOME}/piegalaxy"
fi

if [[ -n "${XDG_CONFIG_HOME}" ]]; then
	configfile="${XDG_CONFIG_HOME}/piegalaxy/piegalaxy.conf"
fi

# Read config file and sanitize input. If you want to change the defaults.
if [[ -f "${configfile}" ]]; then
	if grep -E -q -v '^#|^[^ ]*=[^;]*' "{$configfile}"; then
		echo "Config file is unclean, cleaning it..." >&2
		mv "${configfile}" "$(dirname "${configfile}")/dirty.conf"
		grep -E '^#|^[^ ]*=[^;&]*' "$(dirname "${configfile}")/dirty.conf" >"${configfile}"
	fi
	# shellcheck source=/dev/null
	source "${configfile}"
fi

# shellcheck source=exceptions
source "${exceptions}"

_depends() {
	if ! [[ -x "$(command -v dialog)" ]]; then
		echo "dialog not installed." >"$(tty)"
		sleep 10
		_exit 1
	fi

	# Possibly temporary fix
	if grep -q "wyvern-1.3.0-armv7" "${HOME}/ARES-Setup/scriptmodules/ports/piegalaxy.sh"; then
		curl -s "https://raw.githubusercontent.com/Retro-Arena/pie-galaxy/master/scriptmodule.sh" >"${HOME}/ARES-Setup/scriptmodules/ports/piegalaxy.sh"
		sudo "${HOME}/ARES-Setup/ares_packages.sh" piegalaxy || {
			_error "Could not update self, try to update Pie-Galaxy manually"
			_exit
		}
		_msgbox "Found old updater, fetched the new updater and ran it. Please restart Pie-Galaxy"
		_exit

	fi

	if ! [[ -x "${wyvernbin}" ]]; then
		_error "Wyvern not installed." 1
	fi

	if ! [[ -x "${innobin}" ]]; then
		_error "innoextract not installed." 1
	fi

	if ! [[ -x "$(command -v jq)" ]]; then
		_error "jq not installed." 1
	fi

	if ! [[ -x "$(command -v "${renderhtml[0]}")" ]]; then
		renderhtml=(sed 's:\<br\>:\\n:g')
	fi

	if [[ -n "$DISPLAY" ]]; then
		imgViewer=(feh -F -N -Z -Y -q -D 5 --on-last-slide quit)
	fi
}

main() {
	menuOptions=(
		"Connect" "Operations associated with GOG Connect"
		"Library" "List all games you own"
		"Install" "Install a GOG game from an installer"
		"Settings" "Options for ${title}"
		"About" "About this program"
	)

	selected="$(dialog \
		--backtitle "${title}" \
		--cancel-label "Exit" \
		--default-item "${selected}" \
		--menu "Choose one" \
		22 77 16 "${menuOptions[@]}" 3>&1 1>&2 2>&3 >"$(tty)")"

}

_Library() {
	local preSelected
	preSelected="${1}"

	if [[ -z "${preSelected}" ]]; then

		mapfile -t myLibrary < <(jq --raw-output '.games[] | .ProductInfo | .id, .title' <<<"${wyvernls}")

		selectedGame="$(dialog \
			--backtitle "${title}" \
			--ok-label "Details" \
			--default-item "${selectedGame}" \
			--menu "Choose one" 22 77 16 "${myLibrary[@]}" 3>&1 1>&2 2>&3 >"$(tty)" <"$(tty)")"

	else
		selectedGame="${preSelected}"

	fi

	if [[ -n "${selectedGame}" ]]; then
		_description "${selectedGame}"

	fi

}

# Displays the description of a game
# usage _description "${gameID}"
_description() {
	local gameID gameDescription imgArgs gameImageURL
	export gameImage
	gameID="${1}"

	[[ ! -f "${tmpdir}/${gameID}.json" ]] && curl -s "https://api.gog.com/v2/games/${gameID}?locale=en" >"${tmpdir}/${gameID}.json"

	gameName="$(jq --raw-output --argjson var "${gameID}" '.games[] | .ProductInfo | select(.id==$var) | .title' <<<"${wyvernls}")"
	gameDescription="$(jq --raw-output '.description' <"${tmpdir}/${gameID}.json")"
	gameDescription="$(echo "${gameDescription}" | "${renderhtml[@]}")"

	if type "${gameID}_exception" &>/dev/null; then
		printf -v gameDescription '%s\n\n%s\n' "Installer for this game found in the exception list" "${gameDescription}"

	elif [[ "$(jq --raw-output '.isUsingDosBox' <"${tmpdir}/${gameID}.json")" == "true" ]]; then
		printf -v gameDescription '%s\n\n%s\n' "This game is powered by DOSBox" "${gameDescription}"

	elif [[ "$(jq --raw-output '.additionalRequirements' <"${tmpdir}/${gameID}.json")" == "This game is powered by <a href=http://scummvm.org>ScummVM</a>" ]]; then
		printf -v gameDescription '%s\n\n%s\n' "This game is powered by ScummVM" "${gameDescription}"

	elif [[ "$(jq --raw-output '._embedded | .publisher | .name' <"${tmpdir}/${gameID}.json")" == "Cinemaware" ]]; then
		printf -v gameDescription '%s\n\n%s\n' "This is an Amiga game" "${gameDescription}"

	elif [[ "$(jq --raw-output '._embedded | .publisher | .name' <"${tmpdir}/${gameID}.json")" == "SNK CORPORATION" ]]; then
		printf -v gameDescription '%s\n\n%s\n' "This is a NEO-GEO game" "${gameDescription}"
	fi

	if [[ "${showImage}" ]]; then
		imgArgs=(--extra-button --extra-label "Image")
		gameImageURL="$(jq --raw-output '._embedded | .product | ._links | .image | .href' <"${tmpdir}/${gameID}.json")"
		#try a bigger resolution
		gameImageURL="${gameImageURL/_{formatter\}/}"
	fi

	_yesno "${gameDescription}" --title "${gameName}" --ok-label "Download" "${imgArgs[@]}" --help-label "Extras" --help-button --cancel-label "Back" --defaultno

	case "${?}" in
	0)
		# Download button
		_Download
		;;

	1 | 255)
		# Back button
		_Library
		;;

	2)
		# Extras Button
		_extras "${gameID}"
		_Library "${selectedGame}"
		;;

	3)
		# Image button
		[[ ! -f "${tmpdir}/${gameID}.${gameImageURL##*.}" ]] && curl -s "${gameImageURL}" >"${tmpdir}/${gameID}.${gameImageURL##*.}"
		"${imgViewer[@]}" "${tmpdir}/${gameID}.${gameImageURL##*.}" </dev/tty &>/dev/null || _error "Image viewer failed\n${imgViewer[0]} exited with with exit code ${?}"
		_Library "${selectedGame}"
		;;
	esac
}

#List and download extras for a game
_extras() {
	local gameID gameName extrasList selectedExtra
	gameID="${1}"
	gameName="$(jq --raw-output --argjson var "${gameID}" '.games[] | .ProductInfo | select(.id==$var) | .title' <<<"${wyvernls}")"
	mapfile -t extrasList < <(jq --raw-output '._embedded | .bonuses[] | .name, .type.slug' <"${tmpdir}/${gameID}.json")
	if [[ "${#extrasList[@]}" != "0" ]]; then
		selectedExtra="$(dialog \
			--backtitle "${title}" \
			--ok-label "Download" \
			--cancel-label "Back" \
			--menu "Download bonus content for ${gameName}" \
			22 77 16 "${extrasList[@]}" 3>&1 1>&2 2>&3 >"$(tty)")"
		"${wyvernbin}" extras --id "${gameID}" --slug "${selectedExtra}" --output-folder "${downdir}" &>"$(tty)"
	else
		_msgbox "There are no extras available for ${gameName}."
	fi

}

_Connect() {
	availableGames="$("${wyvernbin}" connect ls 2>&1)"

	if _yesno "Available games:\n\n${availableGames##*wyvern} \n\nDo you want to claim the games?"; then
		"${wyvernbin}" connect claim
		_msgbox "Games claimed"
	fi

}

_Download() {
	if [[ -z "${selectedGame}" ]]; then
		_msgbox "No game selected, please use one from your library."
		return

	else
		mkdir -p "${downdir}"
		"${wyvernbin}" down --id "${selectedGame}" --windows-auto --output "${downdir}/" &>"$(tty)" || {
			_error "download failed"
			return
		}
		_msgbox "${gameName} finished downloading."
	fi

}

_checklogin() {
	if grep -q "access_token =" "${HOME}/.config/wyvern/wyvern.toml"; then
		wyvernls="$(timeout 30 "${wyvernbin}" ls --json)" || _error "It took longer than 30 seconds. You may need to log in again.\nLogging in via this UI is not yet developed.\nits easier if you ssh into the Raspberry Pi and run\n\n${wyvernbin} ls\n\nand follow the instructions to login." 1

	else
		_login
	fi
}

_login() {
	local userEmail userPassword tokenCode

	{
		read -r userEmail
		read -r userPassword
		read -r returncode
	} < <(
		dialog --title "Login" \
			--ok-label "Submit" \
			--backtitle "${title}" \
			--insecure \
			--extra-button --extra-label "Code" \
			--colors \
			--mixedform "Login to \ZbGOG.com\ZB required, you have two login options.\nLogin with a code (for use via SSH, etc.).\nOr login via email and password below (beta).\nThe Password is never stored." \
			22 77 0 \
			"Email    :" 1 1 "" 1 12 90 0 0 \
			"Password :" 2 1 "" 2 12 90 0 1 \
			3>&1 1>&2 2>&3 >"$(tty)"
		echo "${?}"
	)

	# if returncode 1 or 255 is returned, it will be put into the email variable instead, this compensates for that.
	[[ "${userEmail}" =~ ^[0-9]+$ ]] && returncode="${userEmail}"

	case "${returncode}" in
	0)
		#routine for login with username and password
		if [[ "${userEmail}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]] && [[ -n "${userPassword}" ]]; then
			#valid email address format and password not empty, trying to log in
			"${wyvernbin}" login --username "${userEmail}" --password "${userPassword}" &>"$(tty)"
			grep -q "access_token =" "${HOME}/.config/wyvern/wyvern.toml" || _yesno "Login unsuccesfull (Beta feature). Try again with same credentials?" && "${wyvernbin}" login --username "${userEmail}" --password "${userPassword}"
			_checklogin
			unset userPassword userEmail
		else
			[[ ! "${userEmail}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]] && _error "Email provided does not have a valid format! Login not attempted."
			[[ -z "${userPassword}" ]] && _error "Password field is empty!  Login not attempted."
			unset userPassword userEmail
			_login
		fi
		;;
	3)
		# routine for login with code
		tokenCode="$(dialog \
			--title "Code" --ok-label "Submit" \
			--colors \
			--backtitle "${title}" --inputbox "To get the login token codes, go to \Zubit.ly/gogcode\ZU\nMake sure that you are redirected to \Z2login.gog.com\Zn.\nThe code will appear in the address field behind the text \Zu&code=\ZU after log in.\n\nIt may be easier to enter the code via via ssh.  This Pi has an IP address of:\n$(getIPAddress)\nRun Pie-Galaxy by typing:\n./ARES/roms/ports/Pie\\ Galaxy.sh" \
			22 77 "" 3>&1 1>&2 2>&3 >"$(tty)")"
		"${wyvernbin}" login --code "${tokenCode}"
		_checklogin
		unset tokenCode
		;;
	1 | 255)
		unset userPassword userEmail tokenCode
		_exit 1
		;;
	esac

	unset userPassword userEmail tokenCode
}

_About() {
	local about githash builddate wyvernVersion innoVersion gitbranch
	githash="$(git --git-dir="${scriptdir}/.git" rev-parse --short HEAD)"
	gitbranch="$(git --git-dir="${scriptdir}/.git" rev-parse --abbrev-ref HEAD)"
	builddate="$(git --git-dir="${scriptdir}/.git" log -1 --date=short --pretty=format:%cd)"
	wyvernVersion="$(${wyvernbin} --version)"
	innoVersion="$("${innobin}" --version -s)"
	read -rd '' about <<_EOF_
Pie Galaxy ${version}-${gitbranch}-${builddate} + ${githash}
innoextract ${innoVersion}
${wyvernVersion}


A GOG client for ARES and other GNU/Linux distributions. It uses Wyvern to download and Innoextract to extract games. Pie Galaxy also provides a user interface navigatable by game controllers and will install games in such a way that it will use native runtimes. It also uses Wyvern to let you claim games available from GOG Connect.
_EOF_
	_msgbox "${about}" --title "About"
}

_Settings() {
	local settingsMenuOptions settingsSelected

	settingsMenuOptions=(
		"Logout" "Logout of ${title}"
	)

	settingsSelected="$(dialog \
		--backtitle "${title}" \
		--cancel-label "Back" \
		--default-item "${selected}" \
		--menu "Choose one" \
		22 77 16 "${settingsMenuOptions[@]}" 3>&1 1>&2 2>&3 >"$(tty)")"

	case "${settingsSelected}" in
		Logout)
			rm "${HOME}/.config/wyvern/wyvern.toml"
			_exit
		;;
	esac
	
}

_Install() {
	local fileSelected setupInfo gameName gameID gameType shortName extension subdir
	fileSelected="$(_fselect "${downdir}")"
	extension="${fileSelected##*.}"
	fileSize="$(du -h "${fileSelected}")"
	fileSize="${fileSize%%	*}"

	if [[ ! -f "${fileSelected}" ]]; then
		_error "No file was selected."
		return
	fi

	case "${extension,,}" in
	"exe")
		setupInfo="$("${innobin}" --gog-game-id "${fileSelected}")"
		gameName="$(awk -F'"' 'NR==1{print $2}' <<<"${setupInfo}")"
		gameID="$("${innobin}" -s --gog-game-id "${fileSelected}")"
		;;

	"sh")
		gameName="$(grep -Poam 1 'label="\K.*' "${fileSelected}")"
		gameName="${gameName% (GOG.com)\"}"
		setupInfo="Can't read info from .sh files yet."
		gameID="0"
		;;

	*)
		_error "$(basename "${fileSelected}")\n${fileSize}\n\nFile extension ${extension} not supported. Supported extensions are exe or sh." --extra-button --extra-label "Delete"
		if [[ "${?}" == "3" ]]; then rm "${fileSelected}"; fi
		return
		;;
	esac

	_yesno "${setupInfo}" --title "${gameName}" --extra-button --extra-label "Delete" --ok-label "Install"

	case $? in
	1 | 255)
		# cancel or esc
		return
		;;

	3)
		#delete
		rm "${fileSelected}" || {
			_error "Unable to delete file!!"
			return
		}
		_msgbox "${fileSelected} deleted."
		return
		;;
	esac

	# If the setup.exe doesn't have the gameID try to fetch it from the gameName and the library.
	[[ -z "${gameID}" ]] && gameID="$(jq --raw-output --arg var "${gameName}" '.games[] | .ProductInfo | select(.title==$var) | .id' <<<"${wyvernls}")"

	if [[ -z "${gameID}" ]]; then
		# If setup.exe still doesn't contain gameID, try guessing the slug, and fetchign the ID that way.
		gameSlug="${gameName// /_}"
		gameSlug="${gameSlug,,}"
		gameID="$(jq --raw-output --arg var "${gameSlug}" '.games[] | .ProductInfo | select(.slug==$var) | .id' <<<"${wyvernls}")"
	fi

	[[ -z "${gameID}" ]] && {
		_error "Cannot determine Game ID,  aborting installation."
		return
	}

	#Sanitize game name
	gameName="${gameName/™/}"
	gameName="${gameName/©/}"
	gameName="${gameName//+([[:blank:]])/ }"

	_extract "${fileSelected}" "${gameName}"

	if type "${gameID}_exception" &>/dev/null; then
		"${gameID}_exception"
		return

	elif [[ ! -d "${tmpdir}/${gameName}" ]]; then
		_error "Extraction did not succeed"
		return
	fi

	gameType="$(_getType "${gameName}")"

	case "${gameType}" in

	"dosbox")
		[[ -d "${dosboxdir}" ]] || {
			_error "Unable to copy game to ${dosboxdir}\n\nThis is probably means DOSBox is not installed.  Please install DOSBox to continue.  At the command line, type sudo apt-get install dosbox"
			return
		}
		[[ ! -d "${dosboxdir}/gog" ]] && mkdir -p "${dosboxdir}/gog"
		mv -f "${tmpdir}/${gameName}" "${dosboxdir}/${gameName}"
		ln -sf "${scriptdir}/dosbox-launcher.sh" "${romdir}/pc/${gameName}.sh" || _error "Failed to create launcher."
		_msgbox "GOG.com game ID: ${gameID}\n$(basename "${fileSelected}") was extracted and installed to ${dosboxdir}" --title "${gameName} was installed."
		;;

	"scummvm")
		shortName=$(find "${tmpdir}/${gameName}" -name '*.ini' -exec grep -Pom 1 'gameid=\K.*' {} \; -quit)
		shortName=${shortName%$'\r'}

		[[ "${extension,,}" == "sh" ]] && subdir="/data"
		mv -f "${tmpdir}/${gameName}${subdir}" "${scummvmdir}/${gameName}.svm" || {
			_error "Uname to copy game to ${scummvmdir}\n\nThis is likely due to no installation of ScummVM."
			return
		}
		echo "${shortName}" >"${scummvmdir}/${gameName}.svm/${shortName}.svm"
		_msgbox "GOG.com game ID: ${gameID}\n$(basename "${fileSelected}") was extracted and installed to ${scummvmdir}\n\nTo finish the installation and open ScummVM and add game, or install lr-scummvm." --title "${gameName} was installed."
		;;

	"neogeo")
		if [[ ! -d "${romdir}/neogeo/" ]] && _yesno "${romdir}/neogeo/ Does not exist.\n\nDo you want to install lr-fbalpha"; then
			sudo ARES-Setup/ares_packages.sh lr-fbalpha

		fi

		if [[ -f "${romdir}/neogeo/neogeo.zip" ]] && _yesno "neogeo.zip already existsts in ${romdir}/neogeo/\n\nDo you want to overwrite?" --defaultno; then
			cp -f "${tmpdir}/${gameName}/game/neogeo.zip" "${romdir}/neogeo/"

		else
			cp "${tmpdir}/${gameName}/game/neogeo.zip" "${romdir}/neogeo/"
		fi

		if [[ "$(find "${tmpdir}/${gameName}" -name '*.zip' ! -name 'neogeo.zip' | wc -l)" == "1" ]]; then
			cp "$(find "${tmpdir}/${gameName}" -name '*.zip' ! -name 'neogeo.zip')" "${romdir}/neogeo/"

		else
			if [[ -f "${tmpdir}/${gameName}/game/kof2000.zip" ]]; then
				cp "${tmpdir}/${gameName}/game/kof2000.zip" "${romdir}/neogeo/"

			elif [[ -f "${tmpdir}/${gameName}/game/kof2002.zip" ]]; then
				cp "${tmpdir}/${gameName}/game/kof2002.zip" "${romdir}/neogeo/"

			elif [[ -f "${tmpdir}/${gameName}/game/samsh5sp.zip" ]]; then
				cp "${tmpdir}/${gameName}/game/samsh5sp.zip" "${romdir}/neogeo/"

			else
				_error "Game not supported yet."
				return
			fi

			_msgbox "GOG.com game ID: ${gameID}\n$(basename "${fileSelected}") was extracted and installed to ${dosboxdir}" --title "${gameName} was installed."

		fi
		;;

	"unsupported")
		_error "${fileSelected} apperantly is unsupported."
		return
		;;
	esac

}

# Extracts a setup file
# Usage: _extract "${fileName}" "${gameName}"
# extracts "${filename}" and moves game to "${tmpdir}/${gameName}"
_extract() {
	local fileSelected extension gameName
	fileSelected="${1}"
	gameName="${2}"
	extension="${fileSelected##*.}"

	case "${extension,,}" in
	"exe")
		#There is a bug in innoextract that missinterprets the filestructure. using dirname & find as a workaround
		local folder
		rm -rf "${tmpdir:?}/output"
		rm -rf "${tmpdir:?}/${gameName}"
		mkdir -p "${tmpdir}/output" || {
			_error "Could not initialize temp folder for extraction"
			return
		}
		"${innobin}" --gog "${fileSelected}" --output-dir "${tmpdir}/output" &>"$(tty)"
		folder="$(dirname "$(find "${tmpdir}/output" -name 'goggame-*.info')")"
		if [[ "${folder}" == "." ]]; then
			# Didn't find goggame-*.info, now we must rely on exception to catch this install.
			folder="${tmpdir}/output/app"
		fi
		if [[ -n "$(ls -A "${folder}/__support/app")" ]]; then
			cp -r "${folder}"/__support/app/* "${folder}/"
		fi
		mv "${folder}" "${tmpdir}/${gameName}"
		;;

	"sh")
		rm -rf "${tmpdir:?}/output"
		rm -rf "${tmpdir:?}/${gameName}"
		mkdir -p "${tmpdir}/output" || {
			_error "Could not initialize temp folder for extraction"
			return
		}
		unzip "${fileSelected}" -d "${tmpdir}/output" &>"$(tty)"
		folder="${tmpdir}/output/data/noarch"
		mv "${folder}" "${tmpdir}/${gameName}"
		;;

	*)
		_error "File extension not supported."
		;;
	esac

}

# Detect the game type
# Usage: _getType "${gameName}"
# returns dosbox, scummvm or neogeo
_getType() {

	local gamePath type
	gamePath="$(jq --raw-output '.playTasks[] | select(.isPrimary==true) | .path' <"${tmpdir}/${1}/"goggame-*.info)"

	if [[ "${gamePath}" == *"DOSBOX"* ]] || [[ -d "${tmpdir}/${1}/DOSBOX" ]] || [[ -d "${tmpdir}/${1}/dosbox" ]]; then
		type="dosbox"

	elif [[ "${gamePath}" == *"scummvm"* ]] || [[ -d "${tmpdir}/${1}/scummvm" ]]; then
		type="scummvm"

	elif [[ "$(find "${tmpdir}/${1}" -name "neogeo.zip")" ]]; then
		type="neogeo"

	else
		_error "Did not find what game it was.\nNot installing."
		return
	fi

	echo "${type:-unsupported}"
}

# dialog --fselect broken out to a function,
# the purpouse is that
# if the screen is smaller then what --fselec can handle
# I can do somethig else
# Usage: _fselect "${fullPath}"
# returns the file that is selected including the full path, if full path is used.
_fselect() {
	local termh windowh dirList selected extension fileName fullPath gameName newDir
	fullPath="${1}"
	termh="$(tput lines)"
	((windowh = "${termh}" - 10))
	[[ "${windowh}" -gt "22" ]] && windowh="22"
	if "${fullFileBrowser}" && [[ "${windowh}" -ge "8" ]]; then
		dialog \
			--backtitle "${title}" \
			--title "${fullPath}" \
			--fselect "${fullPath}/" \
			"${windowh}" 77 3>&1 1>&2 2>&3 >"$(tty)"

	else
		# in case of a very tiny terminal window
		# make an array of the filenames and put them into --menu instead
		dirList=(
			"goto" "Go to directory (keyboard required)"
			".." "Up one directory"
		)

		while read -r folderName; do
			dirList+=("$(basename "${folderName}")" "Directory")

		done < <(find "${fullPath}" -mindepth 1 -maxdepth 1 ! -name '.*' -type d)

		while read -r fileName; do
			extension="${fileName##*.}"
			case "${extension,,}" in
			"exe")
				dirList+=("$(basename "${fileName}")")

				gameName="$("${innobin}" --gog-game-id "${fileName}")"
				gameName="$(awk -F'"' 'NR==1{print $2}' <<<"${gameName}")"
				dirList+=("${gameName}")
				;;

			"sh")
				dirList+=("$(basename "${fileName}")")

				gameName="$(grep -Poam 1 'label="\K.*' "${fileName}")"
				dirList+=("${gameName% (GOG.com)\"}")
				;;
			esac

		done < <(find "${fullPath}" -maxdepth 1 -type f)

		selected="$(dialog \
			--backtitle "${title}" \
			--title "${fullPath}" \
			--menu "Pick a file to install" \
			22 77 16 "${dirList[@]}" 3>&1 1>&2 2>&3 >"$(tty)" <"$(tty)")"

		[[ "${?}" -ge 1 ]] && return

		case "${selected}" in
		"goto")
			newDir="$(_inputbox "Input a directory to go to" "${HOME}/Downloads")"
			_fselect "${newDir}"
			;;
		"..")
			_fselect "${fullPath%/*}"
			;;
		*.sh | *.exe)
			echo "${fullPath}/${selected}"
			;;
		*)
			_fselect "${fullPath}/${selected}"
			;;
		esac

	fi

}

# Ask user for a string
# Usage: _inputbox "My message" "Initial text" [--optional-arguments]
# You can pass additioal arguments to the dialog program
# Backtitle is already set
_inputbox() {
	local msg opts init
	msg="${1}"
	init="${2}"
	shift 2
	opts=("${@}")
	dialog \
		--backtitle "${title}" \
		"${opts[@]}" \
		--inputbox "${msg}" \
		22 77 "${init}" 3>&1 1>&2 2>&3 >"$(tty)" <"$(tty)"
}

# Display a message
# Usage: _msgbox "My message" [--optional-arguments]
# You can pass additioal arguments to the dialog program
# Backtitle is already set
_msgbox() {
	local msg opts
	msg="${1}"
	shift
	opts=("${@}")
	dialog \
		--backtitle "${title}" \
		"${opts[@]}" \
		--msgbox "${msg}" \
		22 77  3>&1 1>&2 2>&3 >"$(tty)" <"$(tty)"
}

# Request user input
# Usage: _yesno "My question" [--optional-arguments]
# You can pass additioal arguments to the dialog program
# Backtitle is already set
# returns the exit code from dialog which depends on the user answer
_yesno() {
	local msg opts
	msg="${1}"
	shift
	opts=("${@}")
	dialog \
		--backtitle "${title}" \
		"${opts[@]}" \
		--yesno "${msg}" \
		22 77 3>&1 1>&2 2>&3 >"$(tty)" <"$(tty)"
	return "${?}"
}

# Display an error
# Usage: _error "My error" [1] [--optional-arguments]
# If the second argument is a number, the program will exit with that number as an exit code.
# You can pass additioal arguments to the dialog program
# Backtitle and title are already set
# Returns the exit code of the dialog program
_error() {
	local msg opts answer exitcode
	msg="${1}"
	shift
	[[ "${1}" =~ ^[0-9]+$ ]] && exitcode="${1}" && shift
	opts=("${@}")
	dialog \
		--backtitle "${title}" \
		--title "ERROR:" \
		"${opts[@]}" \
		--msgbox "${msg}" \
		22 77 3>&1 1>&2 2>&3 >"$(tty)" <"$(tty)"
	answer="${?}"
	[[ -n "${exitcode}" ]] && _exit "${exitcode}"
	return "${answer}"
}

# Checks if ares helper script exists
# sources it
# and enable joy2key for gamepad input
# Usage: _joy2key
_joy2key() {
	if [[ -f "${areshelper}" ]]; then
		local scriptdir="/home/pigaming/ARES-Setup"
		# shellcheck source=/dev/null
		source "${areshelper}"
		joy2keyStart
	fi
}

# Exits the program
# it also clears
# it also does turns off joy2key if the ares helper script exists
_exit() {
	clear
	if [[ -f "${areshelper}" ]]; then
		joy2keyStop
	fi
	exit "${1:-0}"
}

_joy2key
_depends
_checklogin

while true; do
	main
	"_${selected:-exit}"
done

_exit
