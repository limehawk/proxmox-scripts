#!/bin/bash
# Auto Install Script for SBC Linux
function main()
{
	[ $(id -u) -eq 0 ] || fail "You have to be the root to run the installation"
	
	[ -z "$(which wget)" ] && fail "wget is missing"

	notify_prerequisites

	checkos
	checkpkg 3cxpbx && fail "3CX PBX detected" "it's not possible to install both the PBX and SBC on a machine at the same time"
	
	while ! ask_license
	do
		ask_cancel && cancel
	done

	aptlist=/etc/apt/sources.list.d/3cxpbx.list
	tcxurl=http://downloads-global.3cx.com	
	echo "deb $tcxurl/downloads/debian $os_code main" > $aptlist
	
	apttestinglist=/etc/apt/sources.list.d/3cxpbx-testing.list
	machinearch="$(dpkg --print-architecture)"
	echo "deb [arch=$machinearch] $tcxurl/downloads/debian $os_code-testing main" > $apttestinglist
	
	wget -t 1 -T 10 -qO - "$tcxurl/downloads/3cxpbx/public.key" | apt-key add -
	[ ${PIPESTATUS[1]} -eq 0 ] || fail "$tcxurl is unreachable"
	
	cfg=/etc/3cxsbc.conf
	cfgnew=$(mktemp)
	
	[ -f $cfg ] && parse_config $cfg
	
	while true
	do
		while true
		do
			prompt_url
			res=$?
	
			[ $res -eq 3 ] && ask_cancel && cancel
			[ $res -eq 2 ] && notify_invalid url "$pbx_url" || [ $res -eq 0 ] && break
			[ $res -eq 1 ] && notify_insecure
		done
	
		while ! prompt_key
		do
			ask_cancel && cancel
		done
	
		cfg_url=$pbx_url/sbc/$pbx_key
	
		echo "connecting $pbx_url"	
		wget -T 10 -t 1 -qO $cfgnew $cfg_url && break

		case $? in
		4|5)
			err="Unable to reach the 3CX Server at $pbx_url\nPlease double check \"3CX Provisioning URL\" value and confirm that the SBC Trunk is created properly from within your 3CX Management Console.\n\nAlso 3CX must have a valid secure SSL Certificate so if you have a custom certificate which has expired or not renewed, the installation will fail."
			;;
		8)
			err="The PBX does not accept the SBC AUTHENTICATION KEY ID\n$pbx_key"
			;;
		*)
			err="Unknown error"
		esac
	
		warn "Cannot obtain provisional data" "$err"
		ask_retry "$err" || cancel
	done
	
	sed -i"" -E 's/\r//' $cfgnew
	
	verify_config $cfgnew && parse_config $cfgnew || fail "The provisioning file has successfully been downloaded but is corrupted" "check $cfgnew"
	
	apt-get update -o Dir::Etc::sourcelist=$aptlist -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" \
	&& apt-get update -o Dir::Etc::sourcelist=$apttestinglist -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" \
		&& apt-get -y install 3cxsbc || fail "Cannot install the 3cxsbc package"
	
	[ -f $cfg ] && { chown --reference=$cfg $cfgnew; chmod --reference=$cfg $cfgnew; }
	
	user=$(systemctl show -p User --value 3cxsbc)
	[ -n "$user" ] || user=nobody
	
	group=$(id -gn $user)
	[ -n "$group" ] || group=nogroup
	
	[ -f $cfg ] && chown $user $cfgnew || chown $user:$group $cfgnew
	chmod "u+rw" $cfgnew
	
	mv -f $cfgnew $cfg || fail "Cannot update the configuration file $cfg"
	
	systemctl restart 3cxsbc
	
	echo "INFO: To access the 3CXSBC configuration file type 'sudo nano /etc/3cxsbc.conf'"
	echo "INFO: To enable logs go to 'nano /etc/3cxsbc.conf.local' and set [Log] level to DEBUG"
	echo "INFO: Then restart SBC: systemctl restart 3cxsbc"
	echo "INFO: To open the log file type 'tail -f /var/log/3cxsbc/3cxsbc.log'"
	
	systemctl is-active --quiet 3cxsbc || { tail /var/log/3cxsbc/3cxsbc.log; fail "3CXSBC has failed to start"; }
	
	echo "${tgreen}3CXSBC is up and running. You can now restart your IP Phones and access the 3CX Management Console > Phones node to provision your IP Phones.$tdef"
	
	notify_finish
}

tred=$(tput setaf 1)
tgreen=$(tput setaf 2)
tyellow=$(tput setaf 3)
tdef=$(tput sgr0)

declare -A ptrn
ptrn[num]=0-9
ptrn[hex]=0-9A-Fa-f
ptrn[alnum]=a-zA-Z0-9
ptrn[authority]="((([${ptrn[alnum]}-]+\.)*[${ptrn[alnum]}-]+)|[${ptrn[hex]}:]+)"
ptrn[url]="(((https?):\/\/)([^:/ ]+|(\[[^]]+\]))(:([0-9]+))?)([?/][${ptrn[alnum]}/%&=._-]*)?"

function fail()
{
	echo -e "${tred}error: $1$tdef" >&2
	shift
	for msg in "$@"
	do
		echo -e "       $tred$msg$tdef" >&2
	done
	exit 1
}

function warn()
{
	echo -e "${tyellow}warning: $1$tdef" >&2
	shift
	for msg in "$@"
	do
		echo -e "         $tyellow$msg$tdef" >&2
	done
}

function cancel()
{
	echo "${tred}Installation aborted${tdef}"
	exit 1
}

function match_ptrn()
{
	local pattern=${ptrn[$2]}
	[ -n "$3" ] && sed -nE "s/^${pattern}$/\\$3/p" <<< "$1" || grep -qE "^$pattern$" <<< "$1"
}

function match_url()
{
	local str=$1
	local piece=$2

	local flt_auth="s/^\[(.*)\]$/\1/"

	declare -A pieces
	pieces=( [base]=1 [scheme]=3 [authority]=4 [port]=7 [path]=8 )

	if [ -z "$piece" ]
	then
		 match_ptrn "$str" url || return $?

		 local authority=$(match_ptrn "$str" url ${pieces[authority]} | sed -E "$flt_auth")
		 match_ptrn "$authority" authority
		 return $?
	fi

	local i=${pieces[$piece]}
	[ -z "$i" ] && return 1

	local value=$(echo -n "$str" | sed -nE "s/^${ptrn[url]}$/\\$i/p")
	[ $piece == authority ] && sed -E "$flt_auth" <<< $value || echo $value
	return 0
}

function parse_url()
{
	pbx_scheme=$(match_url "$1" scheme)
	pbx_fqdn=$(match_url "$1" authority)
	pbx_port=$(match_url "$1" port)

	pbx_url=$(match_url "$1" base)

	local path=$(match_url "$1" path)

	local key=$(echo -n $path | sed -nE "s/^\/sbc\/([${ptrn[alnum]}]+)$/\1/p")
	[ -n "$key" ] && pbx_key="$key"
}

backtitle="3CX Session Border Controller Setup"
width=62
height=12

function checkpkg()
{
	dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -qF "ok installed"
}

function checkos()
{
	local path=/etc/os-release

	[ -z "$(which dpkg-query)" ] && fail "Cannot find the package manager (is it a Debian?)"
	checkpkg systemd && [ -f $path ]|| fail "Cannot find systemd (is it a Debian?)"

	os_name=$(sed -nE "s/^\s*ID\"?=(.*)\"?$/\1/p" $path)
	os_parent_name=$(sed -nE "s/^\s*ID_LIKE\"?=(.*)\"?$/\1/p" $path)
	os_version=$(sed -nE "s/^\s*VERSION_ID=\"?([0-9]+)\"?$/\1/p" $path)
	os_code=$(sed -nE "s/^\s*VERSION=\"?$os_version\s*\((.*)\)\"?$/\1/p" $path)

	[ "$os_name" == debian ] || echo "$os_parent_name" | grep -q debian || fail "Unsupported distribution $os_name"
	[ $os_version -ge 9 ] || [ "$os_code" == "stretch" ] || fail "Unsupported Debian version $os_code"
}

function notify_prerequisites()
{
    echo "3CX SBC Pre-requisites:"
    echo "1. Port 5060 UDP on this computer must be free"
    echo "2. Requires 3CX PBX Version 16 or Version 18"
    echo "3. Update 3CX PBX before you install SBC"
    echo
}

function ask_license()
{
    echo "End-User License Agreement"
    echo "$(license)"
    echo
    echo "Do you accept the license? (yes/no)"
    read -r accept
    [[ "$accept" == "yes" ]] || exit 1
}

function prompt_text()
{
    local var=$1
    local text=$2
    eval "local tmp=\$$var"
    echo "$text"
    read -r tmp
    eval "$var='$tmp'"
}

function prompt_url()
{
	local title="Provisioning URL"
	local text="SBC Client for Linux requires the full Provisioning URL of your PBX including the leading \"https://\" protocol and port number at the end.\nExamples: https://mycompany.3cx.com or https://mycompany.3cx.com:5001"
	
	prompt_text pbx_url "$text" --title "$title" && [ -n "$pbx_url" ] || return 3
	match_url "$pbx_url" || return 2
	
	parse_url "$pbx_url"
        [ "$pbx_scheme" == "http" ] && return 1

	return 0
}

function notify_invalid()
{
    echo "Warning: '$2' doesn't seem to be a valid $1."
    echo "Do you want to continue? (yes/no)"
    read -r choice
    [[ "$choice" == "yes" ]] || return 1
}

function notify_insecure()
{
    echo "Insecure HTTP mode is not supported. Please, provide an HTTPS URL."
}

function prompt_key()
{
	local title="SBC AUTHENTICATION KEY ID"
	local text="Access the 3CX Management Console > SIP Trunks > Add SBC. An Authentication KEY ID will be generated. Copy this key in the space below."

	prompt_text pbx_key "$text" --title "$title"
}

function ask_cancel()
{
    echo "Are you sure to abort the installation? (yes/no)"
    read -r choice
    [[ "$choice" == "yes" ]] || exit 1
}

function ask_retry()
{
    echo "Error: $1"
    echo "Do you want to retry? (yes/no)"
    read -r choice
    [[ "$choice" == "yes" ]] || exit 1
}

function notify_finish()
{
	local text="3CXSBC is up and running.\nYou can now restart your IP Phones and access the 3CX Management Console > Phones to provision your IP Phones."
	whiptail --backtitle "$backtitle" --msgbox "$text" $height $width
}

function verify_config()
{
	cat "$1" | grep -qF "End of 3CX SBC config file"
}

function access_config()
{
	local path=$1
	local section=$2
	local key=$3
	local value=$4

	declare -A ptrn
	ptrn[eol]="\s*(\s#.*)?$"
	ptrn[section]="^\s*\[[^]]+\]${ptrn[eol]}"
	ptrn[target]="^\s*\[$(echo -n $section | sed -E 's/\//\\\//')\]${ptrn[eol]}"

	if [ -n "$key" ] && [ -n "$value" ]
	then
		if sed -nE "/${ptrn[target]}/,/${ptrn[section]}/p" $path | grep -q "^\s*$key\s*="
		then
			sed -i"" -E "/${ptrn[target]}/,/${ptrn[section]}/{/^\s*$key\s*=/c\
$key=$value
}" $path
		else
			sed -i"" -E "/${ptrn[target]}/a$key=$value" $path
		fi
	else
		if [ -z "$key" ] 
		then
			grep -E "${ptrn[target]}" $path | sed -E "s/^.*\[(.*)\].*$/\1/"
		else
			sed -nE "/${ptrn[target]}/,/^\s*\[[^]]+\]\s*$/p" $path | sed -nE "1d;\$d;/^${ptrn[eol]}/d;s/\s*#.*//;p" | sed -nE "/^\s*$key\s*=/s/^.*=\s*([^[:space:]]+).*/\1/p"
		fi
	fi
}

function parse_config()
{
	local path=$1

	cfg_section="$(access_config $path "Bridge/.*")"
	[ -n "$cfg_section" ] || return 1

	tunnel_addr=$(access_config "$path" "$cfg_section" TunnelAddr)
	tunnel_port=$(access_config "$path" "$cfg_section" TunnelPort)

	local url=$(access_config $path "$cfg_section" ProvLink)
	if [ -n "$url" ] && match_url "$url" 
	then
		parse_url "$url"
	else
		[ -n "$tunnel_addr" ] && pbx_url=https://$tunnel_addr:5001
	fi

	[ -n "$tunnel_addr" ] && [ -n "$tunnel_port" ] && true || false
}

function license()
{
	cat <<EOF
NO EMERGENCY COMMUNICATIONS 

LICENSEE (AS DEFINED BELOW) ACKNOWLEDGES THAT THE SOFTWARE (AS DEFINED BELOW) IS NOT DESIGNED OR INTENDED FOR USE TO CONTACT, OR COMMUNICATE WITH, ANY POLICE AGENCY, FIRE DEPARTMENT, AMBULANCE SERVICE, HOSPITAL OR ANY OTHER EMERGENCY SERVICE OF ANY KIND.  THE SOFTWARE DOES NOT SUPPORT CALLS TO "911," POISON CONTROL CENTERS OR TO ANY OTHER EMERGENCY NUMBER AVAILABLE IN YOUR COMMUNITY.  3CX DISCLAIMS ANY EXPRESS OR IMPLIED WARRANTY OF FITNESS FOR SUCH USES. 

LICENSE AGREEMENT 

3CX Phone System Software 

3CX Software, Ltd. ("3CX") is willing to license, either directly or through  its  resellers, the 3CX Phone System Software defined below, related documentation, and any other material or information relating to such software provided by 3CX to you (personally and/or on behalf of your employer, as applicable) ("Licensee") ONLY IF YOU ACCEPT ALL OF THE TERMS IN THIS LICENSE AGREEMENT ("License"). 

BEFORE YOU CHOOSE THE "AGREE" BUTTON AT THE BOTTOM OF THIS WINDOW, CAREFULLY READ THE TERMS AND CONDITIONS OF THIS LICENSE.  BY CHOOSING THE "AGREE" BUTTON YOU ARE (1) REPRESENTING THAT YOU ARE OVER THE AGE OF 18 AND HAVE THE CAPACITY AND AUTHORITY TO BIND YOURSELF AND YOUR EMPLOYER, AS APPLICABLE, TO THE TERMS OF THIS LICENSE AND (2) CONSENTING ON BEHALF OF YOURSELF AND/OR AS AN AUTHORIZED REPRESENTATIVE OF YOUR EMPLOYER, AS APPLICABLE, TO BE BOUND BY THIS LICENSE.  IF YOU DO NOT AGREE TO ALL OF THE TERMS AND CONDITIONS OF THIS LICENSE, OR DO NOT REPRESENT THE FOREGOING, CHOOSE THE "DECLINE" BUTTON, IN WHICH CASE YOU WILL NOT AND MAY NOT RECEIVE, INSTALL OR USE THE 3CX PHONE SYSTEM SOFTWARE.  ANY USE OF THE 3CX PHONE SYSTEM SOFTWARE OTHER THAN PURSUANT TO THE TERMS OF THIS LICENSE IS A VIOLATION OF U.S. AND INTERNATIONAL COPYRIGHT LAWS AND CONVENTIONS. 


1.  DEFINITIONS 

"Software" - 3CX's 3CX Phone System Software and any and all other 3CX applications and tools and related documentation that 3CX may provide to Licensee, directly or through one or more levels of resellers, in conjunction with the 3CX Phone System Software. 

2.  GRANT OF LICENSE 

Subject to the terms and conditions of this License, 3CX hereby grants to Licensee a limited, personal, nonexclusive, non-sub-licensable, non-transferable license to install on magnetic or optical media and use ONE (1) copy of the Software. 
The license granted to Licensee is expressly made subject to the following limitations:  Licensee may not itself (and shall not permit any third party to): (i) copy, other than as expressly permitted, all or any portion of the Software, except that Licensee may make one copy of the Software for archival purposes for use by Licensee only in the event the Software shall become inoperative; (ii) modify or translate the Software; (iii) modify, alter, or use the software so as to enable more extensions than are authorized in the relevant software purchase agreement; (iv) reverse engineer, decompile or disassemble the Software, in whole or in part, (v) use the Software to directly or indirectly provide a time-sharing or subscription service to any third party or to function as a service bureau or application service provider; (vi) create derivative works based on the Software, except in accordance with clause (ii) of this paragraph; (vii) publicly display the Software; (viii) rent, lease, sublicense, sell, market, distribute, assign, transfer, or otherwise permit access to the Software to any third party; (ix) install and use the Software unless Licensee has installed on such magnetic or optical medium a valid, licensed copy of an operating system compatible with said Software,(x) disregard the simultaneous number of calls limit applicable to the particular version of 3CX Phone System; or (xi) exercise any right to the Software not expressly granted in this License. 
The Software includes software applications and tools licensed to 3CX by third parties, including without limitation: ReSIProcate, which is licensed and copyrighted by SIPFoundry, Inc. and its licensors; PostgreSQL Database 
Management System, which is licensed and copyrighted by The PostgreSQL Global Development Group and The Regents of the University of California.  This third-party software included in the Software is provided AS IS AND WITH ALL FAULTS.  

3.  OWNERSHIP OF SOFTWARE 

This License does not convey to Licensee an interest in or to the Software, but only a limited right of use revocable in accordance with the terms of this License.  The Software is NOT being sold to Licensee.  3CX and its licensors own all rights, title and interest in and to the Software.  No license or other right in or to the Software is being granted to Licensee except for the rights specifically set forth in this License.  Licensee hereby agrees to abide by all applicable laws and international treaties. 

4.  ENTIRE AGREEMENT 

The third party software applications and tools included in the Software are governed by the terms and conditions of this License. 3CX, in its sole discretion, may provide additional third party software to Licensee at any time.  The installation and use of any third party software provided to Licensee by 3CX that is not specifically included in the Software, whether provided on the same media as the Software or separately, is governed by its own license agreement that will be provided to Licensee and which is between the respective third party and Licensee  This License, policies, terms and conditions incorporated by reference represent the entire agreement between 3CX and Licensee. 

5.  UPDATES AND SUPPORT 

3CX may modify the Software at any time, for any reason, and without providing notice of such modification to Licensee.  This License will apply to any such modifications which are rightfully obtained by Licensee unless expressly stated otherwise.  This License does not grant Licensee any right to any maintenance or services, including without limitation, any support, enhancement, modification, bug fix or update to the Software and 3CX is under no obligation to provide or inform Licensee of any such updates, modifications, maintenance or services  

6.  CONFIDENTIALITY 

Licensee acknowledges that the information about  the Software and certain other materials are confidential as provided herein.  3CX's and its licensors' proprietary and confidential information includes any and all information related to the services and/or business of 3CX or its licensors that is treated as confidential or secret by 3CX or its licensors (that is, it is the subject of efforts by 3CX, or its licensors, as applicable, that are reasonable under the circumstances to maintain its secrecy), including, without limitation, (i) information about  the Software; (ii) any and all other information which is disclosed by 3CX to Licensee orally, electronically, visually, or in a document or other tangible form which is either identified as or should be reasonably understood to be confidential and/or proprietary; and, (iii) any notes, extracts, analysis, or materials prepared by Licensee which are copies of or derivative works of 3CX's or its licensors' proprietary or confidential information from which the substance of Confidential Information can be inferred or otherwise understood (the "Confidential Information"). 
Confidential Information shall not include information which Licensee can clearly establish by written evidence: (a) is already lawfully known to or independently developed by Licensee without access to the Confidential Information, (b) is disclosed in non-confidential published materials, (c) is generally known to the public, or (d) is rightfully obtained from any third party without any obligation of confidentiality.   
Licensee agrees not to disclose Confidential Information to any third party and will protect and treat all Confidential Information with the highest degree of care.  Except as otherwise expressly provided in this License, Licensee will not use or make any copies of Confidential Information, in whole or in part, without the prior written authorization of 3CX.  Licensee may disclose Confidential Information if required by statute, regulation, or order of a court of competent jurisdiction, provided that Licensee provides 3CX with prior notice, discloses only the minimum Confidential Information required to be disclosed, and cooperates with 3CX in taking appropriate protective measures.  These obligations shall continue for two years following any termination of this License with respect to Confidential Information. 

7.  NO WARRANTY AND DISCLAIMER OF LIABILITY 

THE SOFTWARE IS WARRANTED TO SUBSTANTIALLY CONFORM TO ITS WRITTEN DOCUMENTATION. AS SOLE AND EXCLUSIVE REMEDY IN THE EVENT OF A BREACH OF THIS WARRANTY, 3CX OR ITS LICENSORS WILL,  REPLACE THE SOFTWARE WITH CONFORMING SOFTWARE, 3CX AND ITS LICENSORS DO NOT MAKE ANY, AND HEREBY SPECIFICALLY DISCLAIM ANY, OTHER REPRESENTATIONS, ENDORSEMENTS, GUARANTIES, OR WARRANTIES, EXPRESS OR IMPLIED, RELATED TO THE SOFTWARE INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTY OF MERCHANTABILITY, , FITNESS FOR A PARTICULAR PURPOSE  3CX does not warrant that use of the Software, or Licensee's ability to use the Software will be uninterrupted, virus free or error free.  Licensee acknowledges that 3CX does not guarantee compatibility between the Software and any future versions thereof.  Licensee acknowledges that 3CX does not and cannot guarantee that Licensee's computer environment will be free from unauthorized intrusion or otherwise guarantee the privacy of Licensee's information.  Licensee will have sole responsibility for the adequate protection and backup of Licensee's data and/or equipment used with the Software.    
LICENSEE'S SOLE EXCLUSIVE REMEDY FOR ANY CLAIM ARISING UNDER THIS LICENSE OR FROM USE OF THE SOFTWARE IS THAT 3CX WILL USE COMMERCIALLY REASONABLE EFFORTS TO PROVIDE LICENSEE WITH A REPLACEMENT FOR ANY DEFECTIVE SOFTWARE OR MEDIA.  3CX AND ITS PARENTS, SUBSIDIARIES, AFFILIATES, SHAREHOLDERS, DIRECTORS, OFFICERS, EMPLOYEES, LICENSORS AND AGENTS (THE "3CX PARTIES") SHALL NOT BE LIABLE UNDER ANY LEGAL THEORY FOR ANY DAMAGES SUFFERED IN CONNECTION WITH THE USE OF THE SOFTWARE, INCLUDING WITHOUT LIMITATION, INDIRECT, SPECIAL, INCIDENTAL, MULTIPLE, CONSEQUENTIAL, PUNITIVE OR EXEMPLARY DAMAGES, INCLUDING, BUT NOT LIMITED TO, LOSS OF PROFITS, DATA OR USE ("EXCLUDED DAMAGES"), EVEN IF ANY PARTY WAS ADVISED OF THE POSSIBILITY OF ANY EXCLUDED DAMAGES OR ANY EXCLUDED DAMAGES WERE FORESEEABLE.  IN THE EVENT OF A FAILURE OF THE ESSENTIAL PURPOSE OF THE EXCLUSIVE REMEDY, AS LICENSEE'S SOLE AND EXCLUSIVE ALTERNATIVE REMEDY, LICENSEE MAY RECEIVE ACTUAL DIRECT DAMAGES UP TO THE AMOUNT PAID BY LICENSEE TO 3CX FOR THE SOFTWARE.  LICENSEE HEREBY EXPRESSLY RELEASES THE 3CX PARTIES FROM ANY AND ALL LIABILITY OR RESPONSIBILITY FOR ANY DAMAGE CAUSED, DIRECTLY OR INDIRECTLY, TO LICENSEE OR ANY THIRD PARTY AS A RESULT OF THE USE OF THE SOFTWARE OR THE INTRODUCTION THEREOF INTO LICENSEE'S COMPUTER ENVIRONMENT. 
The above disclaimer of warranty and liability constitutes an essential part of this License and Licensee acknowledges that Licensee's installation and use of the Software reflect Licensee's acceptance of this disclaimer of warranty and liability. Certain jurisdictions may limit 3CX's and its licensors' ability to disclaim their liability to you, in which case, the foregoing disclaimer shall be construed to limit 3CX's and its licensors' liability to the maximum extent permitted by applicable law. 

8.  TERM AND TERMINATION OF LICENSE 

This License is valid until terminated.  Licensee may terminate this License at any time. This License will terminate immediately if Licensee defaults or breaches any term of this License.  Upon termination of this License for any reason, any right, license or permission granted to Licensee with respect to the Software shall immediately terminate and Licensee hereby undertakes to: (i) immediately cease to use any part of the Software; and (ii) promptly return the Software and all Confidential Information and related material to 3CX and fully destroy, delete and/or de-install any copy of the Software installed or copied by Licensee. The provisions regarding confidentiality, ownership, disclaimers of warranty, limitation of liability, equitable relief and governing law and venue will survive termination of this License indefinitely in accordance with their terms.  

9.  ASSIGNMENT  

The License is personal to Licensee and Licensee agrees not to transfer (by operation of law or otherwise), sublicense, lease, rent, or assign their rights under this License, and any such attempt shall be null and void.  3CX may assign, transfer, or sublicense this License or any rights or obligations thereunder at any time in its sole discretion.  

10.  GOVERNING LAW 

This License shall be governed by and construed in accordance with the laws of the United Kingdom without regard to conflict of law provisions thereto.  Licensee submits to the jurisdiction of any court sitting in the United Kingdom in any action or proceeding arising out of or relating to this Agreement and agrees that all claims in respect of the action or proceeding may be heard and determined in any such court. 3CX may seek injunctive relief in any venue of its choosing. Licensee hereby submits to personal jurisdiction in such courts.  The parties hereto specifically exclude the United Nations Convention on Contracts for the International Sale of Goods and the Uniform Computer Information Transactions Act from this License and any transaction between them that may be implemented in connection with this License.  The original of this License has been written in English.  The parties hereto waive any statute, law, or regulation that might provide an alternative law or forum or to have this License written in any language other than English.  

11.  U.S. GOVERNMENT END USERS 

The Software is a "commercial item," as that term is defined in 48 C.F.R. 2.101 (Oct. 1995), consisting of "commercial computer software" and "commercial computer software documentation," as such terms are used in 48 C.F.R. 12.212 (Sept. 1995).  Consistent with 48 C.F.R. 12.212 and 48 C.F.R. 227.7202-1 through 227.7202-4 (June 1995), all U.S. Government End Users acquire the Software with only those rights set forth herein. 

12.  EQUITABLE RELIEF 

It is agreed that because of the proprietary nature of the Software, 3CX's and its Licensors' remedies at law for a breach by the Licensee of its obligations under this License will be inadequate and that 3CX and its Licensors shall, in the event of such breach, be entitled to, in addition to any other remedy available to it, equitable relief, including injunctive relief, without the posting of any bond and in addition to all other remedies provided under this License or available at law. 

13.  COPYRIGHT NOTICES AND OTHER NOTICES 

The Software is protected by the copyright laws of the United States and all other applicable laws of the United States and other nations and by any international treaties, unless specifically excluded herein. 
ReSIProcate is licensed and copyrighted by SIPFoundry, Inc. and its licensors. PostgreSQL Database Management System is licensed and copyrighted by The PostgreSQL Global Development Group and The Regents of the University of California. 
This product is licensed for United States Patents No. 4,994,926, No. 5,291,302, No. 5,459,584, No. 6,643,034, No. 6,785,021, No. 7,202,978 and Canadian Patents No. 1329852 and No. 2101327  The speech compression algorithm contained in this equipment uses patented technologies belonging to France Télécom, Mitsubishi Electric Corporation, Nippon Telephone and Telegraph Corporation, Université de Sherbrooke and NEC Corporation for which 3CX has obtained the necessary patent license agreement.
EOF
}

main "$@"
