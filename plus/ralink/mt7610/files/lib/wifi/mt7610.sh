#!/bin/sh
# Copyright (c) 2013 OpenWrt
# Copyright (c) 2005-2014, lintel <lintel.huang@gmail.com>
# Copyright (c) 2013, Hoowa <hoowa.sun@gmail.com>
#
# 	描述:MT7610v2/MT7610E/MT7610E uci无线脚本
#	功能：对接uci与mt7610配置文件，
#
#	引用文件请保留作者信息.
#

append DRIVERS "mt7610"

debug() {
  #echo "debug: ""$1"
  echo -n
}

#修复无法重置raiX虚拟接口问题。
reload_mt7610() {
	debug "reload_mt7610"
	local vif
	for vif in rai0 rai1 rai2 rai3 rai4 rai5 rai6 rai7 wdsi0 wdsi1 wdsi2 wdsi3 apclii0; do
	ifconfig $vif down 2>/dev/null
	set_wifi_down $vif
	#debug "ifdown $vif"
	done
	rmmod MT7610_ap 2>/dev/null
	insmod MT7610_ap 2>/dev/null
}

scan_mt7610() {
	debug "scan_mt7610"
	debug "$1 $2 $3"
	local device="$1"
	local ifname="$1"

	mt7610_phy_if=0
	
	#重置整个驱动
#	reload_mt7610

	local i=-1
	
	while grep -qs "^ *rai$((++i)):" /proc/net/dev; do
	debug "found phy$i rai$i inteface"
	let mt7610_phy_if+=1
	done

	mt7610_ap_num=0
	mt7610_wds_num=0
	mt7610_sta_num=0
	mt7610_sta_first=0
	
	config_get vifs "$device" vifs
	
	for vif in $vifs; do
		config_get_bool disabled "$vif" disabled 0
		[ $disabled -eq 0 ] || continue

		config_get mode "$vif" mode
		case "$mode" in
			adhoc)
				echo "mt7610 only support ap+wds+sta!"
			;;
			sta)
				[ ${mt7610_sta_num:-0} -ge 1 ] && {
					echo "mt7610 only support 1 sta!"
				}
				mt7610_sta_num=$(($mt7610_sta_num + 1))
				debug "mt7610_sta_num=$mt7610_sta_num"
			;;
			ap)
				mt7610_ap_num=$(($mt7610_ap_num + 1))
				debug "mt7610_ap_num=$mt7610_ap_num"
				apmode=1
				mt7610_ap_vif="${mt7610_ap_vif:+$mt7610_ap_vif }$vif"
			;;
			wds)
				config_get wds_addr "$vif" bssid
				[ -z "$wds_addr" ] || {
					wds_addr=$(echo "$wds_addr" | tr 'A-F' 'a-f')
					append mt7610_wds "$wds_addr"
				}
			;;
			monitor)
			;;
			*) echo "$device($vif): Invalid mode";;
		esac
	done
	#开始准备该设备的无线配置参数
	mt7610_prepare_config $device
}


mt7610_prepare_config() {

	debug "mt7610_prepare_config"
	
	#获取参数 存储配置的变量 目标配置关键字
	local ssid_num=0 apcli_num=0 mode disabled
	
#准备产生RaX的无线配置
	local device=$1

#获取当前的无线频道
	config_get channel $device channel

#获取当前的802.11无线模式
	config_get hwmode $device mode
	
#获取WMM支持
	config_get wmm $device wmm
	
#获取设备的传输功率
	config_get txpower $device txpower
	
#获取设备的HT（频宽）
	config_get ht $device ht

#获取国家代码	
	config_get country $device country
	
#是否有MAC过滤
	config_get macpolicy $device macpolicy

#MAC地址过滤列表
	config_get maclist $device maclist
#字符格式转义
	ra_maclist="${maclist// /;};"
	
#是否支持GREEN AP功能
	config_get_bool greenap $device greenap 0

	config_get_bool antdiv "$device" diversity
	
	config_get frag "$device" frag 2346
	
	config_get rts "$device" rts 2347
	
	config_get distance "$device" distance

	config_get hidessid "$device" hidden 0
	
#获取该Radio下面的虚拟接口	
	config_get vifs "$device" vifs

	[ "$channel" == "auto" ] && {
	#遵循你共X要求的频道
	countryregion=0
	countryregion_a=10
	}
	
	#大于11的时候支持11-14号频道，5G支持全频段
	[ "$channel" != "auto" ] && {
	[ ${channel:-0} -ge 1 -a ${channel:-0} -le 11 ] && countryregion=0
	[ ${channel:-0} -ge 12 -a ${channel:-0} -le 13 ] && countryregion=1
	[ ${channel:-0} -eq 14 ] && countryregion=31
	[ ${channel:-0} -ge 36 -a ${channel:-0} -le 140 ] && countryregion_a=7
	#debug "channel=$channel countryregion=$countryregion"
	}

#获取虚拟接口的数量，并提前配置SSID
for vif in $vifs; do
	config_get_bool disabled "$vif" disabled 0
	config_get mode "$vif" mode 0
	
	#如果关闭，则略过该vif配置
	[ "$disabled" == "1" ]&& {
	set_wifi_down $vif
	continue
	}
	
	#如果某个SSID接口需要隐藏，则所有的接口都隐藏
	[ "$hidessid" == "0" ] && {
	config_get hidessid $vif hidden 0
	}
	
	[ "$mode" == "sta" ] || [ "$mode" == "wds" ] && {
	continue
	}

	let ssid_num+=1 #SSID Number
	case $ssid_num in
	1)
		config_get ssid1 "$vif" ssid
		;;
	2)
		config_get ssid2 "$vif" ssid
		;;
	3)
		config_get ssid3 "$vif" ssid
		;;
	4)
		config_get ssid4 "$vif" ssid
		;;
	*)
		echo "Only support 4 MSSID!"
		;;
	esac
done

#开始准备HT模式配置，注意HT模式仅在11N下有效。
	HT=1
	HT_CE=1

	case "$ht" in
	20)
      HT=1 
      HT_CE=1
      VHT=0 
      VHT_DN=0
	;;
	20+40)
      HT=1 
      HT_CE=1
      VHT=0 
      VHT_DN=0	  
	 ;;
	20+40+80)
      HT=1 
      HT_CE=1	
      VHT=1 
      VHT_DN=0
	 ;;
	40+80)
      HT=1 
      HT_CE=0	
      VHT=1 
      VHT_DN=1
	 ;;
	40)
      HT=1 
      HT_CE=1	
      VHT=0 
      VHT_DN=0
	 ;;
	80)
      HT=1 
      HT_CE=1
      VHT=1 
      VHT_DN=1	  
	 ;;
	*)
		echo "unknow ht mode!"
		;;	
	esac	  


	# 在HT40模式下,需要另外的一个频道，如果EXTCHA=1,则当前第二频道为$channel + 4.
	# 如果EXTCHA=0,则当前的第二频道为$channel - 4.
	# 如果当前频道被限制在1-4,则是当前频道+ 4，若否，则为当前频道-4 
	
	EXTCHA=1
	
	[ "$channel" != "auto" ] && [ "$channel" -lt "5" ] && EXTCHA=0

#配置自动选择无线频道
    [ "$channel" == "auto" ] && {
        channel=149
        AutoChannelSelect=2 #增强型自动频道选择
    }

#开始判断WiFi的MAC过滤方式.
    case "$macpolicy" in
	allow|2)
	ra_macfilter=1;
	;;
	deny|1)
	ra_macfilter=2;
	;;
	*|disable|none|0)
	ra_macfilter=0;
	;;
    esac

	#FIXME:单独的STA模式无法启动。
	[ "$mt7610_ap_num" = "0" ] && [ "$mt7610_sta_num" = "1" ] && {
	 ssid_num=1
	}
					
	cat > /tmp/MT7610.dat<<EOF
#The word of "Default" must not be removed
Default
CountryRegion=${countryregion:-0}
CountryRegionABand=${countryregion_a:-10}
CountryCode=US
BssidNum=${ssid_num:-1}
SSID1=${ssid1:-OpenWrt_5G_SSID1}
SSID2=${ssid2:-OpenWrt_5G_SSID2}
SSID3=${ssid3:-OpenWrt_5G_SSID3}
SSID4=${ssid4:-OpenWrt_5G_SSID4}
WirelessMode=${hwmode:-14}
TxRate=0
Channel=${channel:-11}
BasicRate=15
BeaconPeriod=100
DtimPeriod=1
TxPower=${txpower:-100}
DisableOLBC=0
BGProtection=0
MaxStaNum=0
TxPreamble=0
RTSThreshold=${rts:-2347}
FragThreshold=${frag:-2346}
TxBurst=1
PktAggregate=0
TurboRate=0
WmmCapable=${wmm:-0}
APSDCapable=0
DLSCapable=0
APAifsn=3;7;1;1
APCwmin=4;4;3;2
APCwmax=6;10;4;3
APTxop=0;0;94;47
APACM=0;0;0;0
BSSAifsn=3;7;2;2
BSSCwmin=4;4;3;2
BSSCwmax=10;10;4;3
BSSTxop=0;0;94;47
BSSACM=0;0;0;0
AckPolicy=0;0;0;0
NoForwarding=0
NoForwardingBTNBSSID=0
HideSSID=${hidessid:-0}
StationKeepAlive=0
ShortSlot=1
AutoChannelSelect=${AutoChannelSelect:-0}
IEEE8021X=0
IEEE80211H=0
CSPeriod=10
WirelessEvent=0
IdsEnable=0
AuthFloodThreshold=32
AssocReqFloodThreshold=32
ReassocReqFloodThreshold=32
ProbeReqFloodThreshold=32
DisassocFloodThreshold=32
DeauthFloodThreshold=32
EapReqFooldThreshold=32
PreAuth=0
AuthMode=OPEN
EncrypType=NONE
RekeyInterval=0
RekeyMethod=DISABLE
PMKCachePeriod=10
WPAPSK1=
WPAPSK2=
WPAPSK3=
WPAPSK4=
DefaultKeyID=1
Key1Type=0
Key1Str1=
Key1Str2=
Key1Str3=
Key1Str4=
Key2Type=0
Key2Str1=
Key2Str2=
Key2Str3=
Key2Str4=
Key3Type=0
Key3Str1=
Key3Str2=
Key3Str3=
Key3Str4=
Key4Type=0
Key4Str1=
Key4Str2=
Key4Str3=
Key4Str4=
HSCounter=0
AccessPolicy0=${ra_macfilter:-0}
AccessControlList0=${ra_maclist:-0}
AccessPolicy1=0
AccessControlList1=
AccessPolicy2=0
AccessControlList2=
AccessPolicy3=0
AccessControlList3=
WdsEnable=0
WdsEncrypType=NONE
WdsList=
WdsKey=
RADIUS_Server=192.168.2.3
RADIUS_Port=1812
RADIUS_Key=ralink
own_ip_addr=192.168.5.234
EAPifname=br0
PreAuthifname=br0
HT_HTC=0
HT_RDG=0
HT_EXTCHA=0
HT_LinkAdapt=0
HT_OpMode=0
HT_MpduDensity=5
HT_BW=1
HT_AutoBA=1
HT_AMSDU=0
HT_BAWinSize=64
HT_GI=1
HT_LDPC=0
HT_MCS=33
HT_BSSCoexistence=${HT_CE:-1}
VHT_BW=1
VHT_SGI=1
VHT_STBC=0
VHT_BW_SIGNAL=0
VHT_DisallowNonVHT=${VHT_DN:-0}
VHT_LDPC=0
MeshId=MESH
MeshAutoLink=1
MeshAuthMode=OPEN
MeshEncrypType=NONE
MeshWPAKEY=
MeshDefaultkey=1
MeshWEPKEY=
WscManufacturer=
WscModelName=
WscDeviceName=
WscModelNumber=
WscSerialNumber=
RadioOn=1
PMFMFPC=0
PMFMFPR=0
PMFSHA256=0
LoadCodeMethod=0
EOF

}
disable_mt7610() {
	debug "disable_mt7610"
	local vif
	for vif in rai0 rai1 rai2 rai3 rai4 rai5 rai6 rai7 wdsi0 wdsi1 wdsi2 wdsi3 apclii0; do
	ifconfig $vif down 2>/dev/null
	set_wifi_down $vif
	#debug "ifdown $vif"
	done
	
	true
}

mt7610_start_vif() {
	local vif="$1"
	local ifname="$2"

	local net_cfg
	net_cfg="$(find_net_config "$vif")"
	[ -z "$net_cfg" ] || start_net "$ifname" "$net_cfg"

	set_wifi_up "$vif" "$ifname"
}

enable_mt7610_wps_pbc() {
echo "ok"
}

enable_mt7610() {
	
	#传参过来的第一个参数是device
	local device="$1" dmode if_num=-1;
	debug "enable_mt7610"

	#检查并创建WiFi驱动配置链接
	[ -f /etc/Wireless/RT2860/MT7610E.dat ] || {
	mkdir -p /etc/Wireless/RT2860/ 2>/dev/null
	ln -s /tmp/MT7610.dat /etc/Wireless/RT2860/MT7610E.dat 2>/dev/null
	}
	
	#重置整个驱动
	reload_mt7610
	debug "mt7610_ap_num=$mt7610_ap_num"
	config_get_bool disabled "$device" disabled 0	
	if [ "$disabled" = "1" ] ;then
	return
	fi
	
	#开始准备该设备的无线配置参数
#	mt7610_prepare_config $device
	
	config_get dmode $device mode
	config_get vifs "$device" vifs
	
	config_get maxassoc $device maxassoc 0
	
	local mt7610_vifs mt7610_ap_vifs  mt7610_sta_vifs mt7610_wds_vifs
	
	for vif in $vifs; do
		debug "vifs vif=$vif"
		config_get mode "$vif" mode
		[ "$mode" == "ap" ] && {
			mt7610_ap_vifs="$mt7610_ap_vifs $vif"
		}
		[ "$mode" == "sta" ] && {
			mt7610_sta_vifs="$mt7610_sta_vifs $vif"
		}
		[ "$mode" == "wds" ] && {
			mt7610_wds_vifs="$mt7610_ap_vifs $vif"
		}
	done
	
	mt7610_vifs="$mt7610_vifs$mt7610_ap_vifs $mt7610_sta_vifs $mt7610_wds_vifs "
	
#	for vif in $vifs; do
	for vif in $mt7610_vifs; do
		config_get_bool disabled $vif disabled 0
		#如果关闭，则略过该vif配置
		[ "$disabled" == "1" ]&& {
			continue
		}
		
		local ifname encryption key ssid mode
		
#		config_get ifname $vif device			
		config_get encryption $vif encryption
		config_get key $vif key
		config_get ssid $vif ssid
		config_get mode $vif mode
		config_get wps $vif wps

		#获取WPS配置信息
		local wps pin
		config_get wps $vif wps 
		config_get pin $vif pin
		
		#是否隔离客户端
		config_get isolate $vif isolate 0
		
		#802.11h
		config_get doth $vif doth 0

#		config_get hidessid $vif hidden 0	

		#排除如果设置为sta wds
		[ "$mode" != "sta" ] && [ "$mode" != "wds" ] && {
		let if_num+=1
		debug "if_num=$if_num"
		
		#根据ifname数量配置多SSID
		ifname="rai$if_num"
		}
		
		#STA APClient配置
		[ "$mode" == "sta" ] && {

					[ "$mt7610_ap_num" = "0" ] && [ "$mt7610_sta_num" = "1" ] || [ "$if_num" == "-1" ]&& {
						#初始化phy
						ifconfig rai0 up
					}
					
					#如果为apcli模式，指定接口名称为apcli0
					ifname="apclii0"
					
					echo "#Encryption" >/tmp/wifi_encryption_${ifname}.dat
#					ifconfig $ifname up
					config_get bssid $vif bssid 0
					[ -z "$mode" ] && {
					#iwpriv $ifname set ApCliBssid=$bssid
					echo "APCli use bssid connect."
					}
			case "$encryption" in
				none)
					echo "NONE" >>/tmp/wifi_encryption_${ifname}.dat
					apctrl $ifname connect $ssid  $key &
					;;
				WEP|wep|wep-open)
					echo "WEP" >>/tmp/wifi_encryption_${ifname}.dat
					apctrl $ifname connect $ssid  $key &
					;;
				WEP-SHARE|wep-shared)
					echo "WEP" >>/tmp/wifi_encryption_${ifname}.dat
					apctrl $ifname connect $ssid  $key &
					;;
				WPA*|wpa*|WPA2-PSK|psk*)
					echo "WPA2" >>/tmp/wifi_encryption_${ifname}.dat
					apctrl $ifname connect $ssid  $key &
					echo "WPAPSKWPA2PSK" >>/tmp/wifi_encryption_${ifname}.dat
					echo "TKIPAES" >>/tmp/wifi_encryption_${ifname}.dat
					;;
			esac
					ifconfig $ifname up
					#FIXME:单独STA模式
					[ "$mt7610_ap_num" = "0" ] && [ "$mt7610_sta_num" = "1" ] && {
						ifconfig rai0 down
					}
		}
		#AP模式配置
		[ "$mode" == "ap" ] && {
			[ "$key" = "" -a "$vif" = "private" ] && {
				logger "no key set serial"
				key="AAAAAAAAAA"
			}
			[ "$dmode" == "6" ] && wpa_crypto="aes"
			ifconfig $ifname up
			#判断当前加密模式
			echo "#Encryption" >/tmp/wifi_encryption_${ifname}.dat
			iwpriv $ifname set "SSID=${ssid}"
			case "$encryption" in
				#找到WPA/WPA2加密
				wpa*|psk*|WPA*|Mixed|mixed)
					echo "WPA" >>/tmp/wifi_encryption_${ifname}.dat
					local enc
					case "$encryption" in
						Mixed|mixed|psk+psk2)
							enc=WPAPSKWPA2PSK
							;;
						WPA2*|wpa2*|psk2*)
							enc=WPA2PSK
							;;
						WPA*|WPA1*|wpa*|wpa1*|psk*)
							enc=WPAPSK
							;;
					esac
					local crypto="TKIPAES"
					case "$encryption" in
					*tkip+aes*|*tkip+ccmp*|*aes+tkip*|*ccmp+tkip*)
						crypto="TKIPAES"
						;;
					*aes*|*ccmp*)
						crypto="AES"
						;;
					*tkip*) 
						crypto="TKIP"
						echo Warring!!! TKIP not support in 802.11n 40Mhz!!!
					;;
					esac
					echo "$enc" >>/tmp/wifi_encryption_${ifname}.dat
					echo "$crypto" >>/tmp/wifi_encryption_${ifname}.dat
					iwpriv $ifname set AuthMode=$enc
					iwpriv $ifname set EncrypType=$crypto
					iwpriv $ifname set IEEE8021X=0
					iwpriv $ifname set "SSID=${ssid}"
					iwpriv $ifname set "WPAPSK=${key}"
					iwpriv $ifname set DefaultKeyID=2
					iwpriv $ifname set "SSID=${ssid}"
					
					#配置WPS	
					if [ "$wps" == "pbc" ]  && [ "$encryption" != "none" ]; then {
					enable_mt7610_wps_pbc $ifname
					touch /tmp/"$ifname"_wps_pbc.lock 2>/dev/null
					}
					else
					rm -rf /tmp/"$ifname"_wps_pbc.lock 2>/dev/null
					fi;	
					;;
				WEP|wep|wep-open|wep-shared)
					echo "WEP" >>/tmp/wifi_encryption_${ifname}.dat
					iwpriv $ifname set AuthMode=WEPAUTO
					iwpriv $ifname set EncrypType=WEP
					iwpriv $ifname set IEEE8021X=0
					for idx in 1 2 3 4; do
						config_get keyn $vif key${idx}
						[ -n "$keyn" ] && iwpriv $ifname set "Key${idx}=${keyn}"
					done
					iwpriv $ifname set DefaultKeyID=${key}
					iwpriv $ifname set "SSID=${ssid}"
					echo 
					#iwpriv $ifname set WscConfMode=0
					;;
				none|open)
					echo "NONE" >>/tmp/wifi_encryption_${ifname}.dat
					iwpriv $ifname set AuthMode=OPEN
					#iwpriv $ifname set WscConfMode=0
					iwpriv $ifname set EncrypType=NONE
					#iwpriv $ifname set WscConfMode=0
					;;
			esac
		}
		
		#如果关闭了WIFI，则关闭RF
		if [ $disabled == 1 ]; then
		 iwpriv $ifname set RadioOn=0
		 set_wifi_down $ifname
		else
		 iwpriv $ifname set RadioOn=1
		fi
		
		#隔离客户端连接。
		[ $isolate == "1" ]&&{
			iwpriv $ifname set NoForwarding=1
		}
		
		#802.11h 支持
		[ $doth == "1" ]&&{
			iwpriv $ifname set IEEE80211H=1
		}	
		
		ifconfig "$ifname" up
		if [ "$mode" == "sta" ];then {
			net_cfg="$(find_net_config "$vif")"
			[ -z "$net_cfg" ] || {
					mt7610_start_vif "$vif" "$ifname"

			}
		}
		else
		{
			local net_cfg bridge
			net_cfg="$(find_net_config "$vif")"
			[ -z "$net_cfg" ]||{
				bridge="$(bridge_interface "$net_cfg")"
				config_set "$vif" bridge "$bridge"
				mt7610_start_vif "$vif" "$ifname"
				#Fix bridge problem
				[ -z `brctl show |grep $ifname` ] && {
				brctl addif $(bridge_interface "$net_cfg") $ifname
				}
				
			}



		}
		fi;
		
		set_wifi_up "$vif" "$ifname"
		debug "set vif=$vif $ifname up"
	done

	#配置无线最大连接数
	iwpriv $device set MaxStaNum=$maxassoc
}

#获取MAC地址
mt7610_get_mac() {
#	/lib/functions.sh
	factory_part=$(find_mtd_part $1)
	dd bs=1 skip=32772 count=6 if=$factory_part 2>/dev/null | /usr/sbin/maccalc bin2mac	
}

#detect_mt7610函数用于检测是否存在驱动
detect_mt7610() {
	local i=-1
#判断系统是否存在mt7610_ap，不存在则退出
	cd /sys/module/
	[ -d MT7610_ap ] || return
	
#检查并创建WiFi驱动配置链接
	[ -f /etc/Wireless/RT2860/MT7610E.dat ] || {
	mkdir -p /etc/Wireless/RT2860/ 2>/dev/null
	touch /tmp/MT7610.dat
	ln -s /tmp/MT7610.dat /etc/Wireless/RT2860/MT7610E.dat 2>/dev/null
	}
	
#检测系统存在多少个wifi接口
	while grep -qs "^ *rai$((++i)):" /proc/net/dev; do
		config_get type rai${i} type
		[ "$type" = mt7610 ] && continue
	
	
		cat <<EOF
config wifi-device  rai${i}
	option type     mt7610
	option mode 	14
	option channel  auto
	option txpower 100
	option ht 20+40+80
	option country US
	
# REMOVE THIS LINE TO ENABLE WIFI:
	option disabled 0	
	
config wifi-iface
	option device   rai${i}
	option network	lan
	option mode     ap
	option doth     1
	option ssid     OpenWrt-5G
	option encryption none
	
EOF

	done

}


