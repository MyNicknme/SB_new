#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
[[ $EUID -ne 0 ]] && yellow "Пожалуйста, запустите скрипт от имени root" && exit
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else 
red "Скрипт не поддерживает текущую систему, пожалуйста, используйте Ubuntu, Debian или Centos." && exit
fi
export sbfiles="/etc/s-box/sb10.json /etc/s-box/sb11.json /etc/s-box/sb.json"
export sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
#if [[ $(echo "$op" | grep -i -E "arch|alpine") ]]; then
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
red "Скрипт не поддерживает текущую систему $op, пожалуйста, используйте Ubuntu, Debian или Centos." && exit
fi
version=$(uname -r | cut -d "-" -f1)
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
case $(uname -m) in
armv7l) cpu=armv7;;
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "На данный момент скрипт не поддерживает архитектуру $(uname -m)" && exit;;
esac
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
bbr=`sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}'`
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
bbr="Openvz версия bbr-plus"
else
bbr="Openvz/Lxc"
fi
hostname=$(hostname)

touch sbyg_update
if [ ! -f sbyg_update ]; then
green "Установка необходимых зависимостей для скрипта Sing-box-yg..."
if [[ x"${release}" == x"alpine" ]]; then
apk update
apk add jq openssl iproute2 iputils coreutils expect git socat iptables grep tar tzdata dcron util-linux
apk add virt-what
else
if [[ $release = Centos && ${vsid} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/ 
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
yum clean all && yum makecache
cd
fi
if [ -x "$(command -v apt-get)" ]; then
apt update -y
apt install jq cron socat iptables-persistent coreutils util-linux -y
elif [ -x "$(command -v yum)" ]; then
yum update -y && yum install epel-release -y
yum install jq socat coreutils util-linux -y
elif [ -x "$(command -v dnf)" ]; then
dnf update -y
dnf install jq socat coreutils util-linux -y
fi
if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
if [ -x "$(command -v yum)" ]; then
yum install -y cronie iptables-services
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie iptables-services
fi
systemctl enable iptables >/dev/null 2>&1
systemctl start iptables >/dev/null 2>&1
fi
if [[ -z $vi ]]; then
apt install iputils-ping iproute2 systemctl -y
fi

packages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
inspackages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
for i in "${!packages[@]}"; do
package="${packages[$i]}"
inspackage="${inspackages[$i]}"
if ! command -v "$package" &> /dev/null; then
if [ -x "$(command -v apt-get)" ]; then
apt-get install -y "$inspackage"
elif [ -x "$(command -v yum)" ]; then
yum install -y "$inspackage"
elif [ -x "$(command -v dnf)" ]; then
dnf install -y "$inspackage"
fi
fi
done
fi
touch sbyg_update
fi

if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
red "TUN не обнаружен, пытаюсь добавить поддержку TUN" && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
green "Не удалось добавить поддержку TUN, рекомендуется связаться с провайдером VPS или включить его в панели управления" && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "Служба мониторинга TUN запущена"
fi
fi
fi
v4v6(){
v4=$(curl -s4m5 icanhazip.com -k)
v6=$(curl -s6m5 icanhazip.com -k)
v4dq=$(curl -s4m5 -k https://ip.fm | sed -E 's/.*Location: ([^,]+,[^,]+,[^,]+),.*/\1/' 2>/dev/null)
v6dq=$(curl -s6m5 -k https://ip.fm | sed -E 's/.*Location: ([^,]+,[^,]+,[^,]+),.*/\1/' 2>/dev/null)
}
warpcheck(){
wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

v6(){
v4orv6(){
if [ -z "$(curl -s4m5 icanhazip.com -k)" ]; then
echo
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
yellow "Обнаружен VPS только с IPv6, добавляю NAT64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf
ipv=prefer_ipv6
else
ipv=prefer_ipv4
fi
if [ -n "$(curl -s6m5 icanhazip.com -k)" ]; then
endip="2606:4700:d0::a29f:c001"
xsdns="[2001:4860:4860::8888]"
sbyx="ipv6_only"
else
endip="162.159.192.1"
xsdns="8.8.8.8"
sbyx="ipv4_only"
fi
}
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4orv6
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
v4orv6
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

argopid(){
ym=$(cat /etc/s-box/sbargoympid.log 2>/dev/null)
ls=$(cat /etc/s-box/sbargopid.log 2>/dev/null)
}

close(){
systemctl stop firewalld.service >/dev/null 2>&1
systemctl disable firewalld.service >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -t mangle -F >/dev/null 2>&1
iptables -F >/dev/null 2>&1
iptables -X >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
if [[ -n $(apachectl -v 2>/dev/null) ]]; then
systemctl stop httpd.service >/dev/null 2>&1
systemctl disable httpd.service >/dev/null 2>&1
service apache2 stop >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
fi
sleep 1
green "Открытие портов и отключение фаервола завершено"
}

openyn(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "Открыть порты и отключить фаервол?\n1. Да, выполнить (Enter по умолчанию)\n2. Нет, пропустить! (настрою сам)\nПожалуйста, выберите [1-2]:" action
if [[ -z $action ]] || [[ "$action" = "1" ]]; then
close
elif [[ "$action" = "2" ]]; then
echo
else
red "Ошибка ввода, пожалуйста, выберите снова" && openyn
fi
}

inssb(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "Какую версию ядра использовать?"
yellow "1：Использовать последнюю официальную версию (Enter по умолчанию)"
yellow "2：Использовать предыдущую официальную версию 1.10.7"
readp "Пожалуйста, выберите [1-2]:" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
else
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"1\.10[0-9\.]*",'  | sed -n 1p | tr -d '",')
fi
sbname="sing-box-$sbcore-linux-$cpu"
curl -L -o /etc/s-box/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
blue "Успешно установлено ядро Sing-box версии: $(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
else
red "Файл ядра Sing-box скачан не полностью, установка не удалась, пожалуйста, попробуйте еще раз" && exit
fi
else
red "Не удалось скачать ядро Sing-box, попробуйте еще раз и проверьте доступ VPS к Github" && exit
fi
}

inscertificate(){
ymzs(){
ym_vl_re=apple.com
echo
blue "SNI домен для Vless-reality по умолчанию apple.com"
tlsyn=true
ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
certificatec_vmess_ws='/root/ygkkkca/cert.crt'
certificatep_vmess_ws='/root/ygkkkca/private.key'
certificatec_hy2='/root/ygkkkca/cert.crt'
certificatep_hy2='/root/ygkkkca/private.key'
certificatec_tuic='/root/ygkkkca/cert.crt'
certificatep_tuic='/root/ygkkkca/private.key'
certificatec_an='/root/ygkkkca/cert.crt'
certificatep_an='/root/ygkkkca/private.key'
}

zqzs(){
ym_vl_re=apple.com
echo
blue "SNI домен для Vless-reality по умолчанию apple.com"
tlsyn=false
ym_vm_ws=www.bing.com
certificatec_vmess_ws='/etc/s-box/cert.pem'
certificatep_vmess_ws='/etc/s-box/private.key'
certificatec_hy2='/etc/s-box/cert.pem'
certificatep_hy2='/etc/s-box/private.key'
certificatec_tuic='/etc/s-box/cert.pem'
certificatep_tuic='/etc/s-box/private.key'
certificatec_an='/etc/s-box/cert.pem'
certificatep_an='/etc/s-box/private.key'
}

red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "II. Генерация и настройка сертификатов"
echo
blue "Автоматическая генерация самоподписанного сертификата bing..." && sleep 2
openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key
openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=www.bing.com"
echo
if [[ -f /etc/s-box/cert.pem ]]; then
blue "Самоподписанный сертификат bing успешно создан"
else
red "Не удалось создать самоподписанный сертификат bing" && exit
fi
echo
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
yellow "Обнаружено, что ранее с помощью скрипта Acme-yg был получен сертификат: $(cat /root/ygkkkca/ca.log) "
green "Использовать сертификат домена $(cat /root/ygkkkca/ca.log)?"
yellow "1：Нет! Использовать самоподписанный сертификат (Enter по умолчанию)"
yellow "2：Да! Использовать сертификат домена $(cat /root/ygkkkca/ca.log)"
readp "Пожалуйста, выберите [1-2]:" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
ymzs
fi
else
green "Если у вас есть привязанный домен, хотите получить сертификат Acme?"
yellow "1：Нет! Продолжить использование самоподписанного сертификата (Enter по умолчанию)"
yellow "2：Да! Получить сертификат Acme через скрипт Acme-yg (поддерживает 80 порт и DNS API)"
readp "Пожалуйста, выберите [1-2]:" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
bash <(curl -Ls https://raw.githubusercontent.com/MyNicknme/Acme/refs/heads/main/Acme-yonggekkk.sh)
if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
red "Ошибка получения сертификата Acme, продолжаем с самоподписанным сертификатом" 
zqzs
else
ymzs
fi
fi
fi
}

chooseport(){
if [[ -z $port ]]; then
port=$(shuf -i 10000-65535 -n 1)
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nПорт занят, пожалуйста, введите другой порт" && readp "Свой порт:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nПорт занят, пожалуйста, введите другой порт" && readp "Свой порт:" port
done
fi
blue "Подтвержденный порт: $port" && sleep 2
}

vlport(){
readp "\nУстановите порт Vless-reality (Enter для случайного порта от 10000 до 65535):" port
chooseport
port_vl_re=$port
}
vmport(){
readp "\nУстановите порт Vmess-ws (Enter для случайного порта от 10000 до 65535):" port
chooseport
port_vm_ws=$port
}
hy2port(){
readp "\nУстановите основной порт Hysteria2 (Enter для случайного порта от 10000 до 65535):" port
chooseport
port_hy2=$port
}
tu5port(){
readp "\nУстановите основной порт Tuic5 (Enter для случайного порта от 10000 до 65535):" port
chooseport
port_tu=$port
}
anport(){
readp "\nУстановите основной порт Anytls, доступен в новых ядрах (Enter для случайного порта):" port
chooseport
port_an=$port
}

insport(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "III. Настройка портов протоколов"
yellow "1：Автоматически генерировать случайный порт для каждого протокола (10000-65535), Enter по умолчанию"
yellow "2：Настроить порты вручную"
readp "Пожалуйста, выберите [1-2]:" port
if [ -z "$port" ] || [ "$port" = "1" ] ; then
ports=()
for i in {1..5}; do
while true; do
port=$(shuf -i 10000-65535 -n 1)
if ! [[ " ${ports[@]} " =~ " $port " ]] && \
[[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
[[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
ports+=($port)
break
fi
done
done
port_vm_ws=${ports[0]}
port_vl_re=${ports[1]}
port_hy2=${ports[2]}
port_tu=${ports[3]}
port_an=${ports[4]}
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
until [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_vm_ws") ]]
do
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
done
echo
blue "В зависимости от использования TLS в Vmess-ws, автоматически выбран стандартный порт для CDN: $port_vm_ws"
else
vlport && vmport && hy2port && tu5port
if [[ "$sbnh" != "1.10" ]]; then
anport
fi
fi
echo
blue "Подтвержденные порты протоколов:"
blue "Порт Vless-reality: $port_vl_re"
blue "Порт Vmess-ws: $port_vm_ws"
blue "Порт Hysteria-2: $port_hy2"
blue "Порт Tuic-v5: $port_tu"
if [[ "$sbnh" != "1.10" ]]; then
blue "Порт Anytls: $port_an"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "IV. Автоматическая генерация общего UUID (пароля) для протоколов"
uuid=$(/etc/s-box/sing-box generate uuid)
blue "Подтвержденный UUID (пароль): ${uuid}"
blue "Подтвержденный путь Vmess (path): ${uuid}-vm"
}

inssbjsonser(){
cat > /etc/s-box/sb10.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",
            "sniff": true,
            "sniff_override_destination": true,
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        }
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag": "vps-outbound-v4", 
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag": "vps-outbound-v6",
"domain_strategy":"prefer_ipv6"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
},
{
"type":"direct",
"tag":"socks-IPv4-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"socks-IPv6-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"direct",
"tag":"warp-IPv4-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"warp-IPv6-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"wireguard",
"tag":"wireguard-out",
"server":"$endip",
"server_port":2408,
"local_address":[
"172.16.0.2/32",
"${v6}/128"
],
"private_key":"$pvk",
"peer_public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"reserved":$res
},
{
"type": "block",
"tag": "block"
}
],
"route":{
"rules":[
{
"protocol": [
"quic",
"stun"
],
"outbound": "block"
},
{
"outbound":"warp-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"warp-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v4",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF

cat > /etc/s-box/sb11.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",

      
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",


        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",


        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",

     
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        },
        {
            "type":"anytls",
            "tag":"anytls-sb",
            "listen":"::",
            "listen_port":${port_an},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
            "tls":{
                "enabled": true,
                "certificate_path": "$certificatec_an",
                "key_path": "$certificatep_an"
            }
        }
],
"endpoints":[
{
"type":"wireguard",
"tag":"warp-out",
"address":[
"172.16.0.2/32",
"${v6}/128"
],
"private_key":"$pvk",
"peers": [
{
"address": "$endip",
"port":2408,
"public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"allowed_ips": [
"0.0.0.0/0",
"::/0"
],
"reserved":$res
}
]
}
],
 "dns": {
    "servers": [
      {
        "type": "https",
        "server": "${xsdns}"
      }
    ],
    "strategy": "${sbyx}"
  },
"outbounds": [
{
"type":"direct",
"tag":"direct"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
}
],
"route":{
"rules":[
{
 "action": "sniff"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv4"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv6"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"socks-out"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"warp-out"
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
}

sbservice(){
if [[ x"${release}" == x"alpine" ]]; then
echo '#!/sbin/openrc-run
description="sing-box service"
command="/etc/s-box/sing-box"
command_args="run -c /etc/s-box/sb.json"
command_background=true
pidfile="/var/run/sing-box.pid"' > /etc/init.d/sing-box
chmod +x /etc/init.d/sing-box
rc-update add sing-box default
rc-service sing-box start
else
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl start sing-box
systemctl restart sing-box
fi
}

ipuuid(){
if [[ x"${release}" == x"alpine" ]]; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl status sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
v4v6
if [[ -n $v4 && -n $v6 ]]; then
green "Настройка вывода конфигурации IPv4/IPv6"
yellow "1: Обновить локальный IP, использовать IPv4 (Enter по умолчанию) "
yellow "2: Обновить локальный IP, использовать IPv6"
readp "Пожалуйста, выберите [1-2]:" menu
if [ -z "$menu" ] || [ "$menu" = "1" ]; then
sbdnsip='tls://8.8.8.8/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="$v4"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v4"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="[$v6]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v6"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
else
yellow "VPS не является двухстековым (Dual Stack), переключение IP не поддерживается"
serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
if [[ "$serip" =~ : ]]; then
sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="[$serip]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
sbdnsip='tls://8.8.8.8/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="$serip"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
fi
else
red "Служба Sing-box не запущена" && exit
fi
}

wgcfgo(){
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
ipuuid
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
ipuuid
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

result_vl_vm_hy_tu(){
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
ym=`bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'`
echo $ym > /root/ygkkkca/ca.log
fi
rm -rf /etc/s-box/vm_ws_argo.txt /etc/s-box/vm_ws.txt /etc/s-box/vm_ws_tls.txt
sbdnsip=$(cat /etc/s-box/sbdnsip.log)
server_ip=$(cat /etc/s-box/server_ip.log)
server_ipcl=$(cat /etc/s-box/server_ipcl.log)
uuid=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')
vl_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].listen_port')
vl_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')
public_key=$(cat /etc/s-box/public.key)
short_id=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.reality.short_id[0]')
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
ws_path=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
if [[ "$tls" = "false" ]]; then
if [[ -f /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
else
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ip
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
if [[ -f /etc/s-box/cfvmadd_local.txt ]]; then
vmadd_local=$(cat /etc/s-box/cfvmadd_local.txt 2>/dev/null)
vmadd_are_local=$(cat /etc/s-box/cfvmadd_local.txt 2>/dev/null)
else
if [[ "$tls" = "false" ]]; then
if [[ -f /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
else
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ip
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
fi
if [[ -f /etc/s-box/cfvmadd_argo.txt ]]; then
vmadd_argo=$(cat /etc/s-box/cfvmadd_argo.txt 2>/dev/null)
else
vmadd_argo=www.visa.com.sg
fi
hy2_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
if [[ -n $hy2_ports ]]; then
hy2ports=$(echo $hy2_ports | sed 's/:/-/g')
hyps=$hy2_port,$hy2ports
else
hyps=
fi
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
if [[ "$hy2_sniname" = '/etc/s-box/private.key' ]]; then
hy2_name=www.bing.com
sb_hy2_ip=$server_ip
cl_hy2_ip=$server_ipcl
ins_hy2=1
hy2_ins=true
else
hy2_name=$ym
sb_hy2_ip=$ym
cl_hy2_ip=$ym
ins_hy2=0
hy2_ins=false
fi
tu5_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
tu5_name=www.bing.com
sb_tu5_ip=$server_ip
cl_tu5_ip=$server_ipcl
ins=1
tu5_ins=true
else
tu5_name=$ym
sb_tu5_ip=$ym
cl_tu5_ip=$ym
ins=0
tu5_ins=false
fi
an_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].listen_port')
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
an_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
if [[ "$an_sniname" = '/etc/s-box/private.key' ]]; then
an_name=www.bing.com
sb_an_ip=$server_ip
cl_an_ip=$server_ipcl
ins_an=1
an_ins=true
else
an_name=$ym
sb_an_ip=$ym
cl_an_ip=$ym
ins_an=0
an_ins=false
fi
}

resvless(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
vl_link="vless://$uuid@$server_ip:$vl_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname"
echo "$vl_link" > /etc/s-box/vl_reality.txt
red "🚀 Инфо о узле [ vless-reality-vision ]:" && sleep 2
echo
echo "Ссылка для шеринга [v2rayN (ядро sing-box), nekobox, Shadowrocket]"
echo -e "${yellow}$vl_link${plain}"
echo
echo "QR-код [v2rayN (ядро sing-box), nekobox, Shadowrocket]"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vl_reality.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resvmess(){
if [[ "$tls" = "false" ]]; then
argopid
if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀 Инфо о временном узле [ vmess-ws(tls)+Argo ] (можно выбрать 3-8-3, кастомный адрес CDN):" && sleep 2
echo
echo "Ссылка для шеринга [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "QR-код [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argols.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argols.txt)"
fi
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
argogd=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀 Инфо о постоянном узле [ vmess-ws(tls)+Argo ] (можно выбрать 3-8-3, кастомный адрес CDN):" && sleep 2
echo
echo "Ссылка для шеринга [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "QR-код [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argogd.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argogd.txt)"
fi
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀 Инфо о узле [ vmess-ws ] (рекомендуется 3-8-1 для настройки CDN):" && sleep 2
echo
echo "Ссылка для шеринга [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "QR-код [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws.txt)"
else
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀 Инфо о узле [ vmess-ws-tls ] (рекомендуется 3-8-1 для настройки CDN):" && sleep 2
echo
echo "Ссылка для шеринга [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "QR-код [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_tls.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_tls.txt)"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

reshy2(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&mport=$hyps&sni=$hy2_name#hy2-$hostname"
#hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&sni=$hy2_name#hy2-$hostname"
echo "$hy2_link" > /etc/s-box/hy2.txt
red "🚀 Инфо о узле [ Hysteria-2 ]:" && sleep 2
echo
echo "Ссылка для шеринга [v2rayn, v2rayng, nekobox, Shadowrocket]"
echo -e "${yellow}$hy2_link${plain}"
echo
echo "QR-код [v2rayn, v2rayng, nekobox, Shadowrocket]"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/hy2.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

restu5(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
tuic5_link="tuic://$uuid:$uuid@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&allow_insecure=$ins&allowInsecure=$ins#tu5-$hostname"
echo "$tuic5_link" > /etc/s-box/tuic5.txt
red "🚀 Инфо о узле [ Tuic-v5 ]:" && sleep 2
echo
echo "Ссылка для шеринга [v2rayn, nekobox, Shadowrocket]"
echo -e "${yellow}$tuic5_link${plain}"
echo
echo "QR-код [v2rayn, nekobox, Shadowrocket]"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/tuic5.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resan(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
an_link="anytls://$uuid@$sb_an_ip:$an_port?&sni=$an_name&allowInsecure=$ins_an#anytls-$hostname"
echo "$an_link" > /etc/s-box/an.txt
red "🚀 Инфо о узле [ Anytls ]:" && sleep 2
echo
echo "Ссылка для шеринга [v2rayn, Shadowrocket]"
echo -e "${yellow}$an_link${plain}"
echo
echo "QR-код [v2rayn, nekobox, Shadowrocket]"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/an.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

sb_client(){
sbany1(){
  if [[ "$sbnh" != "1.10" ]]; then
    echo "\"anytls-$hostname\","
  fi
}
clany1(){
  if [[ "$sbnh" != "1.10" ]]; then
    echo "- anytls-$hostname"
  fi
}
sbany2(){
  if [[ "$sbnh" != "1.10" ]]; then
    cat <<EOF
         {
            "type": "anytls",
            "tag": "anytls-$hostname",
            "server": "$sb_an_ip",
            "server_port": $an_port,
            "password": "$uuid",
            "idle_session_check_interval": "30s",
            "idle_session_timeout": "30s",
            "min_idle_session": 5,
            "tls": {
                "enabled": true,
                "insecure": $an_ins,
                "server_name": "$an_name"
            }
         },
EOF
  fi
}
clany2(){
  if [[ "$sbnh" != "1.10" ]]; then
    cat <<EOF
- name: anytls-$hostname
  type: anytls
  server: $cl_an_ip
  port: $an_port
  password: $uuid
  client-fingerprint: chrome
  udp: true
  idle-session-check-interval: 30
  idle-session-timeout: 30
  sni: $an_name
  skip-cert-verify: $an_ins
EOF
  fi
}

sball(){
cat <<EOF
{
    "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
    },
    "experimental": {
        "cache_file": {
            "enabled": true,
            "path": "./cache.db",
            "store_fakeip": true
        },
        "clash_api": {
            "external_controller": "127.0.0.1:9090",
            "external_ui": "ui",
            "default_mode": "Rule"
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "aliDns",
                "type": "https",
                "server": "dns.alidns.com",
                "path": "/dns-query",
                "domain_resolver": "local"
            },
            {
                "tag": "local",
                "type": "udp",
                "server": "223.5.5.5"
            },
            {
                "tag": "proxyDns",
                "type": "https",
                "server": "dns.google",
                "path": "/dns-query",
                "domain_resolver": "aliDns",
                "detour": "proxy"
            },
           {
        "type": "fakeip",
        "tag": "fakeip",
        "inet4_range": "198.18.0.0/15",
        "inet6_range": "fc00::/18"
      }
        ],
        "rules": [
            {
                "rule_set": "geosite-cn",
                "clash_mode": "Rule",
                "server": "aliDns"
            },
            {
                "clash_mode": "Direct",
                "server": "local"
            },
            {
                "clash_mode": "Global",
                "server": "proxyDns"
            },
            {
        "query_type": [
          "A",
          "AAAA"
        ],
        "server": "fakeip"
      }
        ],
        "final": "proxyDns",
        "strategy": "ipv4_only",
        "independent_cache": true
    },
    "inbounds": [
        {
            "type": "tun",
            "tag": "tun-in",
            "address": [
                "172.19.0.1/30",
                "fd00::1/126"
            ],
            "auto_route": true,
            "strict_route": true
        }
    ],
    "route": {
        "rules": [
            {
               "inbound": "tun-in",
                "action": "sniff"
            },
            {
                "type": "logical",
                "mode": "or",
                "rules": [
                    {
                        "port": 53
                    },
                    {
                        "protocol": "dns"
                    }
                ],
                "action": "hijack-dns"
            },
         {
          "clash_mode": "Global",
          "outbound": "proxy"
         },
        {
        "rule_set": "geosite-cn",
        "clash_mode": "Rule",
        "outbound": "direct"
       },
     {
    "rule_set": "geoip-cn",
    "clash_mode": "Rule",
    "outbound": "direct"
      },
     {
    "ip_is_private": true,
    "clash_mode": "Rule",
    "outbound": "direct"
    },
     {
      "clash_mode": "Direct",
      "outbound": "direct"
     }      
        ],
        "rule_set": [
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "direct"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "direct"
            }
        ],
        "final": "proxy",
        "auto_detect_interface": true,
        "default_domain_resolver": {
            "server": "aliDns"
        }
    },
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
            },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
  0             "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
EOF
}

clall(){
cat <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: true 
  listen: "0.0.0.0:1053"
  ipv6: true
  prefer-h3: false
  respect-rules: true
  use-system-hosts: false
  cache-algorithm: "arc"
  enhanced-mode: "fake-ip"
  fake-ip-range: "198.18.0.1/16"
  fake-ip-filter:
    - "+.lan"
    - "+.local"
    - "+.msftconnecttest.com"
    - "+.msftncsi.com"
    - "localhost.ptlogin2.qq.com"
    - "localhost.sec.qq.com"
    - "+.in-addr.arpa"
    - "+.ip6.arpa"
    - "time.*.com"
    - "time.*.gov"
    - "pool.ntp.org"
    - "localhost.work.weixin.qq.com"
  default-nameserver: ["223.5.5.5", "1.2.4.8"]
  nameserver:
    - "https://208.67.222.222/dns-query"
    - "https://1.1.1.1/dns-query"
    - "https://8.8.4.4/dns-query"
  proxy-server-nameserver:
    - "https://223.5.5.5/dns-query"
    - "https://doh.pub/dns-query"
  nameserver-policy:
    "geosite:private,cn":
      - "https://223.5.5.5/dns-query"
      - "https://doh.pub/dns-query"

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                      
  client-fingerprint: chrome                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins
EOF
}

tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
argopid
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) && -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
$(sball)
$(sbany2)
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo-постоянный-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo-постоянный-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo-временный-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo-временный-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
        {
            "tag": "proxy",
            "type": "selector",
            "default": "auto",
            "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        $(sbany1)
        "vmess-tls-argo-постоянный-$hostname",
        "vmess-argo-постоянный-$hostname",
        "vmess-tls-argo-временный-$hostname",
        "vmess-argo-временный-$hostname"
            ]
        },
        {
            "tag": "auto",
            "type": "urltest",
            "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        $(sbany1)
        "vmess-tls-argo-постоянный-$hostname",
        "vmess-argo-постоянный-$hostname",
        "vmess-tls-argo-временный-$hostname",
        "vmess-argo-временный-$hostname"
            ],
            "url": "http://www.gstatic.com/generate_204",
            "interval": "10m",
            "tolerance": 50
        },
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
$(clall)

$(clany2)

- name: vmess-tls-argo-постоянный-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd


- name: vmess-argo-постоянный-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"       000000                         
    headers:
      Host: $argogd

- name: vmess-tls-argo-временный-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo

- name: vmess-argo-временный-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo 

proxy-groups:
- name: Балансировка-нагрузки
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-постоянный-$hostname
    - vmess-argo-постоянный-$hostname
    - vmess-tls-argo-временный-$hostname
    - vmess-argo-временный-$hostname

- name: Автовыбор
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-постоянный-$hostname
    - vmess-argo-постоянный-$hostname
    - vmess-tls-argo-временный-$hostname
    - vmess-argo-временный-$hostname
    
- name: 🌍Выбор-прокси-узла
  type: select
  proxies:
    - Балансировка-нагрузки                                         
    - Автовыбор
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-постоянный-$hostname
    - vmess-argo-постоянный-$hostname
    - vmess-tls-argo-временный-$hostname
    - vmess-argo-временный-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍Выбор-прокси-узла
EOF


elif [[ ! -n $(ps -e | grep -w $ym 2>/dev/null) && -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
$(sball)
$(sbany2)
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo-временный-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo-временный-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
        {
            "tag": "proxy",
            "type": "selector",
            "default": "auto",
            "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        $(sbany1)
        "vmess-tls-argo-временный-$hostname",
        "vmess-argo-временный-$hostname"
            ]
        },
        {
            "tag": "auto",
            "type": "urltest",
            "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
  0     "tuic5-$hostname",
        $(sbany1)
        "vmess-tls-argo-временный-$hostname",
        "vmess-argo-временный-$hostname"
            ],
            "url": "http://www.gstatic.com/generate_204",
            "interval": "10m",
            "tolerance": 50
        },
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
$(clall)








$(clany2)

- name: vmess-tls-argo-временный-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo

- name: vmess-argo-временный-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo 

proxy-groups:
- name: Балансировка-нагрузки
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-временный-$hostname
    - vmess-argo-временный-$hostname

- name: Автовыбор
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-временный-$hostname
    - vmess-argo-временный-$hostname
    
- name: 🌍Выбор-прокси-узла
  type: select
  proxies:
    - Балансировка-нагрузки                                         
    - Автовыбор
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-временный-$hostname
    - vmess-argo-временный-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍Выбор-прокси-узла
EOF

elif [[ -n $(ps -e | grep -w $ym 2>/dev/null) && ! -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
$(sball)
$(sbany2)
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo-постоянный-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo-постоянный-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
        {
            "tag": "proxy",
            "type": "selector",
            "default": "auto",
            "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        $(sbany1)
        "vmess-tls-argo-постоянный-$hostname",
        "vmess-argo-постоянный-$hostname"
            ]
        },
        {
            "tag": "auto",
            "type": "urltest",
            "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        $(sbany1)
        "vmess-tls-argo-постоянный-$hostname",
        "vmess-argo-постоянный-$hostname"
            ],
            "url": "http://www.gstatic.com/generate_204",
            "interval": "10m",
            "tolerance": 50
        },
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
$(clall)






$(clany2)

- name: vmess-tls-argo-постоянный-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd

- name: vmess-argo-постоянный-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"       000000                         
    headers:
      Host: $argogd

proxy-groups:
- name: Балансировка-нагрузки
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-постоянный-$hostname
    - vmess-argo-постоянный-$hostname

- name: Автовыбор
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-постоянный-$hostname
    - vmess-argo-постоянный-$hostname
    
- name: 🌍Выбор-прокси-узла
  type: select
  proxies:
    - Балансировка-нагрузки                                         
    - Автовыбор
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo-постоянный-$hostname
    - vmess-argo-постоянный-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍Выбор-прокси-узла
EOF

else
cat > /etc/s-box/sing_box_client.json <<EOF
$(sball)
$(sbany2)
        {
            "tag": "proxy",
            "type": "selector",
            "default": "auto",
            "outbounds": [
        "auto",
        "vless-$hostname",
        $(sbany1)
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname"
            ]
        },
        {
            "tag": "auto",
            "type": "urltest",
            "outbounds": [
        "vless-$hostname",
        $(sbany1)
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname"
            ],
            "url": "http://www.gstatic.com/generate_204",
            "interval": "10m",
            "tolerance": 50
        },
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
$(clall)

$(clany2)

proxy-groups:
- name: Балансировка-нагрузки
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)

- name: Автовыбор
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    
- name: 🌍Выбор-прокси-узла
  type: select
  proxies:
    - Балансировка-нагрузки                                         
    - Автовыбор
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍Выбор-прокси-узла
EOF
fi
}

cfargo_ym(){
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
echo
yellow "1: Временный туннель Argo"
yellow "2: Постоянный туннель Argo"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-2]:" menu
if [ "$menu" = "1" ]; then
cfargo
elif [ "$menu" = "2" ]; then
cfargoym
else
changeserv
fi
else
yellow "Туннель Argo недоступен, так как для vmess включен TLS" && sleep 2
fi
}

cloudflaredargo(){
if [ ! -e /etc/s-box/cloudflared ]; then
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
esac
curl -L -o /etc/s-box/cloudflared -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
#curl -L -o /etc/s-box/cloudflared -# --retry 2 https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/$cpu
chmod +x /etc/s-box/cloudflared
fi
}

cfargoym(){
echo
if [[ -f /etc/s-box/sbargotoken.log && -f /etc/s-box/sbargoym.log ]]; then
green "Текущий домен постоянного туннеля Argo: $(cat /etc/s-box/sbargoym.log 2>/dev/null)"
green "Текущий токен постоянного туннеля Argo: $(cat /etc/s-box/sbargotoken.log 2>/dev/null)"
fi
echo
green "Пожалуйста, убедитесь, что настройки в Cloudflare (Zero Trust -> Networks -> Tunnels) завершены"
yellow "1: Сбросить/настроить домен постоянного туннеля Argo"
yellow "2: Остановить постоянный туннель Argo"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-2]:" menu
if [ "$menu" = "1" ]; then
cloudflaredargo
readp "Введите токен постоянного туннеля Argo: " argotoken
readp "Введите домен постоянного туннеля Argo: " argoym
if [[ -n $(ps -e | grep cloudflared) ]]; then
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
fi
echo
if [[ -n "${argotoken}" && -n "${argoym}" ]]; then
if pidof systemd >/dev/null 2>&1; then
cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=argo service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/root/agsbx/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${argotoken}"
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload >/dev/null 2>&1
systemctl enable argo >/dev/null 2>&1
systemctl start argo >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1; then
cat > /etc/init.d/argo <<EOF
#!/sbin/openrc-run
description="argo service"
command="/etc/s-box/cloudflared tunnel"
command_args="--no-autoupdate --edge-ip-version auto --protocol http2 run --token ${argotoken}"
pidfile="/run/argo.pid"
command_background="yes"
depend() {
need net
}
EOF
chmod +x /etc/init.d/argo >/dev/null 2>&1
rc-update add argo default >/dev/null 2>&1
rc-service argo start >/dev/null 2>&1
else
nohup setsid /etc/s-box/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${argotoken} >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbargoympid.log
sleep 20
fi
fi
echo ${argoym} > /etc/s-box/sbargoym.log
echo ${argotoken} > /etc/s-box/sbargotoken.log
if ! pidof systemd >/dev/null 2>&1 && ! command -v rc-service >/dev/null 2>&1; then
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid /etc/s-box/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token $(cat /etc/s-box/sbargotoken.log 2>/dev/null) >/dev/null 2>&1 & pid=\$! && echo \$pid > /etc/s-box/sbargoympid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
fi
argo=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
blue "Настройка постоянного туннеля Argo завершена, домен: $argo"
elif [ "$menu" = "2" ]; then
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
if pidof systemd >/dev/null 2>&1; then
systemctl stop argo >/dev/null 2>&1
systemctl disable argo >/dev/null 2>&1
rm -rf /etc/systemd/system/argo.service
elif command -v rc-service >/dev/null 2>&1; then
rc-service argo stop >/dev/null 2>&1
rc-update del argo default >/dev/null 2>&1
rm -rf /etc/init.d/argo
fi
rm -rf /etc/s-box/vm_ws_argogd.txt
green "Постоянный туннель Argo остановлен"
else
cfargo_ym
fi
}

cfargo(){
echo
yellow "1: Сбросить домен временного туннеля Argo"
yellow "2: Остановить временный туннель Argo"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-2]:" menu
if [ "$menu" = "1" ]; then
cloudflaredargo
i=0
while [ $i -le 4 ]; do let i++
yellow "Попытка $i: Проверка валидности домена временного туннеля Argo, пожалуйста, подождите..."
if [[ -n $(ps -e | grep cloudflared) ]]; then
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
fi
nohup setsid /etc/s-box/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
echo "$!" > /etc/s-box/sbargopid.log
sleep 20
if [[ -n $(curl -sL https://$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')/ -I | awk 'NR==1 && /404|400|503/') ]]; then
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
blue "Заявка на временный туннель Argo одобрена, домен подтвержден: $argo" && sleep 2
break
fi
if [ $i -eq 5 ]; then
echo
yellow "Проверка временного домена Argo недоступна, он может восстановиться позже, либо запросите сброс" && sleep 3
fi
done
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid /etc/s-box/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 & pid=\$! && echo \$pid > /etc/s-box/sbargopid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
elif [ "$menu" = "2" ]; then
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
rm -rf /etc/s-box/vm_ws_argols.txt
green "Временный туннель Argo остановлен"
else
cfargo_ym
fi
}

instsllsingbox(){
if [[ -f '/etc/systemd/system/sing-box.service' ]]; then
red "Служба Sing-box уже установлена, повторная установка невозможна" && exit
fi
mkdir -p /etc/s-box
v6
openyn
inssb
inscertificate
insport
sleep 2
echo
blue "Ключи и ID для Vless-reality будут сгенерированы автоматически..."
key_pair=$(/etc/s-box/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" > /etc/s-box/public.key
short_id=$(/etc/s-box/sing-box generate rand --hex 4)
wget -q -O /root/geoip.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
wget -q -O /root/geosite.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "V. Автоматическая генерация аккаунта warp-wireguard для выхода" && sleep 2
warpwg
inssbjsonser
sbservice
sbactive
#curl -sL https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
lnsb && blue "Скрипт Sing-box-yg успешно установлен, ярлык для запуска: sb" && cronsb
echo
wgcfgo
sbshare
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
blue "Для получения настроек V2rayN (Hysteria2/Tuic5), Mihomo/Sing-box и ссылок подписки выберите пункт 9"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

changeym(){
[ -f /root/ygkkkca/ca.log ] && ymzs="$yellowПереключиться на сертификат домена: $(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellowСертификат домена не запрошен, переключение невозможно$plain"
vl_na="Используемый домен: $(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name'). $yellowСменить на домен, подходящий для reality (домены с сертификатами не поддерживаются)$plain"
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
[[ "$tls" = "false" ]] && vm_na="В данный момент TLS отключен. $ymzs ${yellow}Будет включен TLS, туннель Argo станет недоступен${plain}" || vm_na="Используемый сертификат домена: $(cat /root/ygkkkca/ca.log 2>/dev/null). $yellowПереключиться на отключение TLS, туннель Argo станет доступен$plain"
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_na="Используется самоподписанный сертификат bing. $ymzs" || hy2_na="Используемый сертификат домена: $(cat /root/ygkkkca/ca.log 2>/dev/null). $yellowПереключиться на самоподписанный сертификат bing$plain"
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_na="Используется самоподписанный сертификат bing. $ymzs" || tu5_na="Используемый сертификат домена: $(cat /root/ygkkkca/ca.log 2>/dev/null). $yellowПереключиться на самоподписанный сертификат bing$plain"
an_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
[[ "$an_sniname" = '/etc/s-box/private.key' ]] && an_na="Используется самоподписанный сертификат bing. $ymzs" || an_na="Используемый сертификат домена: $(cat /root/ygkkkca/ca.log 2>/dev/null). $yellowПереключиться на самоподписанный сертификат bing$plain"
echo
green "Пожалуйста, выберите протокол для смены режима сертификата"
green "1: протокол vless-reality, $vl_na"
if [[ -f /root/ygkkkca/ca.log ]]; then
green "2: протокол vmess-ws, $vm_na"
green "3: протокол Hysteria2, $hy2_na"
green "4: протокол Tuic5, $tu5_na"
if [[ "$sbnh" != "1.10" ]]; then
green "5: протокол Anytls, $na_na"
fi
else
red "Доступен только вариант 1 (vless-reality). Поскольку сертификат домена не запрошен, варианты для vmess, Hysteria-2, Tuic-v5 и Anytls скрыты"
fi
green "0: Вернуться назад"
readp "Пожалуйста, выберите:" menu
if [ "$menu" = "1" ]; then
readp "Введите домен vless-reality (Enter для apple.com):" menu
ym_vl_re=${menu:-apple.com}
a=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')
b=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.reality.handshake.server')
c=$(cat /etc/s-box/vl_reality.txt | cut -d'=' -f5 | cut -d'&' -f1)
echo $sbfiles | xargs -n1 sed -i "23s/$a/$ym_vl_re/"
echo $sbfiles | xargs -n1 sed -i "27s/$b/$ym_vl_re/"
restartsb
blue "Настройка завершена, вернитесь в главное меню и выберите пункт 9 для обновления конфигурации узлов"
elif [ "$menu" = "2" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
a=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
[ "$a" = "true" ] && a_a=false || a_a=true
b=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
[ "$b" = "www.bing.com" ] && b_b=$(cat /root/ygkkkca/ca.log) || b_b=$(cat /root/ygkkkca/ca.log)
c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.certificate_path')
d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
echo $sbfiles | xargs -n1 sed -i "55s#$a#$a_a#"
echo $sbfiles | xargs -n1 sed -i "56s#$b#$b_b#"
echo $sbfiles | xargs -n1 sed -i "57s#$c#$c_c#"
echo $sbfiles | xargs -n1 sed -i "58s#$d#$d_d#"
restartsb
blue "Настройка завершена, пожалуйста, вернитесь в главное меню и выберите пункт 9 для обновления конфигурации узлов"
echo
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
blue "Текущий порт Vmess-ws(tls): $vm_port"
[[ "$tls" = "false" ]] && blue "Помните: в главном меню (опция 4-2) можно изменить порт Vmess-ws на любой из 7 портов серии 80 (80, 8080, 8880, 2052, 2082, 2086, 2095) для оптимизации IP через CDN" || blue "Помните: в главном меню (опция 4-2) можно изменить порт Vmess-ws-tls на любой из 6 портов серии 443 (443, 8443, 2053, 2083, 2087, 2096) для оптимизации IP через CDN"
echo
else
red "Сертификат домена не оформлен, переключение невозможно. Выберите 12 в главном меню для настройки Acme" && sleep 2 && sb
fi
elif [ "$menu" = "3" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.certificate_path')
d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
echo $sbfiles | xargs -n1 sed -i "79s#$c#$c_c#"
echo $sbfiles | xargs -n1 sed -i "80s#$d#$d_d#"
restartsb
blue "Настройка завершена, пожалуйста, вернитесь в главное меню и выберите пункт 9 для обновления конфигурации узлов"
else
red "Сертификат домена не оформлен, переключение невозможно. Выберите 12 в главном меню для настройки Acme" && sleep 2 && sb
fi
elif [ "$menu" = "4" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.certificate_path')
d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
echo $sbfiles | xargs -n1 sed -i "102s#$c#$c_c#"
echo $sbfiles | xargs -n1 sed -i "103s#$d#$d_d#"
restartsb
blue "Настройка завершена, пожалуйста, вернитесь в главное меню и выберите пункт 9 для обновления конфигурации узлов"
else
red "Сертификат домена не оформлен, переключение невозможно. Выберите 12 в главном меню для настройки Acme" && sleep 2 && sb
fi
elif [ "$menu" = "5" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.certificate_path')
d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
echo $sbfiles | xargs -n1 sed -i "119s#$c#$c_c#"
echo $sbfiles | xargs -n1 sed -i "120s#$d#$d_d#"
restartsb
blue "Настройка завершена, пожалуйста, вернитесь в главное меню и выберите пункт 9 для обновления конфигурации узлов"
else
red "Сертификат домена не оформлен, переключение невозможно. Выберите 12 в главном меню для настройки Acme" && sleep 2 && sb
fi
else
sb
fi
}

allports(){
vl_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].listen_port')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
hy2_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
tu5_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
an_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].listen_port')
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
tu5_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$tu5_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
[[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="Не добавлен"
[[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="Не добавлен"
}

changeport(){
sbactive
allports
fports(){
readp "\nВведите диапазон портов для перенаправления (1000-65535, формат: порт1:порт2):" rangeport
if [[ $rangeport =~ ^([1-9][0-9]{3,4}:[1-9][0-9]{3,4})$ ]]; then
b=${rangeport%%:*}
c=${rangeport##*:}
if [[ $b -ge 1000 && $b -le 65535 && $c -ge 1000 && $c -le 65535 && $b -lt $c ]]; then
iptables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "Диапазон портов перенаправления подтвержден: $rangeport"
else
red "Введенный диапазон портов находится вне допустимых пределов" && fports
fi
else
red "Неверный формат ввода. Используйте формат порт1:порт2" && fports
fi
echo
}
fport(){
readp "\nВведите порт для перенаправления (в диапазоне 1000-65535):" onlyport
if [[ $onlyport -ge 1000 && $onlyport -le 65535 ]]; then
iptables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "Порт перенаправления подтвержден: $onlyport"
else
blue "Введенный порт находится вне допустимых пределов" && fport
fi
echo
}

hy2deports(){
allports
hy2_ports=$(echo "$hy2_ports" | sed 's/,/,/g')
IFS=',' read -ra ports <<< "$hy2_ports"
for port in "${ports[@]}"; do
iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
done
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
}
tu5deports(){
allports
tu5_ports=$(echo "$tu5_ports" | sed 's/,/,/g')
IFS=',' read -ra ports <<< "$tu5_ports"
for port in "${ports[@]}"; do
iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
done
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
}

allports
green "Для Vless-reality, Vmess-ws, Anytls можно изменить только один порт (учитывайте сброс Argo)"
green "Hysteria2 и Tuic5 поддерживают смену основного порта и управление списком дополнительных портов"
green "Hysteria2 поддерживает Port Hopping; оба протокола поддерживают мультиплексирование портов"
echo
green "1: Протокол Vless-reality ${yellow}порт:$vl_port${plain}"
green "2: Протокол Vmess-ws ${yellow}порт:$vm_port${plain}"
green "3: Протокол Hysteria2 ${yellow}порт:$hy2_port  доп. порты: $hy2zfport${plain}"
green "4: Протокол Tuic5 ${yellow}порт:$tu5_port  доп. порты: $tu5zfport${plain}"
if [[ "$sbnh" != "1.10" ]]; then
green "5: Протокол Anytls ${yellow}порт:$an_port${plain}"
fi
green "0: Вернуться назад"
readp "Выберите протокол для смены порта:" menu
if [ "$menu" = "1" ]; then
vlport
echo $sbfiles | xargs -n1 sed -i "14s/$vl_port/$port_vl_re/"
restartsb
blue "Порт Vless-reality изменен, выберите 9 для получения данных конфигурации"
echo
elif [ "$menu" = "5" ]; then
anport
echo $sbfiles | xargs -n1 sed -i "110s/$an_port/$port_an/"
restartsb
blue "Порт Anytls изменен, выберите 9 для получения данных конфигурации"
echo
elif [ "$menu" = "2" ]; then
vmport
echo $sbfiles | xargs -n1 sed -i "41s/$vm_port/$port_vm_ws/"
restartsb
blue "Порт Vmess-ws изменен, выберите 9 для получения данных конфигурации"
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
blue "Помните: если используется Argo, временный туннель нужно перезапустить, а в настройках постоянного туннеля сменить порт на $port_vm_ws"
else
blue "Включение туннеля Argo в данном режиме не поддерживается"
fi
echo
elif [ "$menu" = "3" ]; then
green "1: Сменить основной порт Hysteria2 (доп. порты будут сброшены)"
green "2: Добавить дополнительные порты Hysteria2"
green "3: Сбросить/удалить дополнительные порты Hysteria2"
green "0: Вернуться назад"
readp "Пожалуйста, выберите [0-3]:" menu
if [ "$menu" = "1" ]; then
if [ -n $hy2_ports ]; then
hy2deports
hy2port
echo $sbfiles | xargs -n1 sed -i "67s/$hy2_port/$port_hy2/"
restartsb
result_vl_vm_hy_tu && reshy2 && sb_client
else
hy2port
echo $sbfiles | xargs -n1 sed -i "67s/$hy2_port/$port_hy2/"
restartsb
result_vl_vm_hy_tu && reshy2 && sb_client
fi
elif [ "$menu" = "2" ]; then
green "1: Добавить диапазон портов Hysteria2"
green "2: Добавить одиночный порт Hysteria2"
green "0: Вернуться назад"
readp "Пожалуйста, выберите [0-2]:" menu
if [ "$menu" = "1" ]; then
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
fports && result_vl_vm_hy_tu && sb_client && changeport
elif [ "$menu" = "2" ]; then
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
fport && result_vl_vm_hy_tu && sb_client && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n $hy2_ports ]; then
hy2deports && result_vl_vm_hy_tu && sb_client && changeport
else
yellow "Дополнительные порты для Hysteria2 не установлены" && changeport
fi
else
changeport
fi

elif [ "$menu" = "4" ]; then
green "1: Сменить основной порт Tuic5 (доп. порты будут сброшены)"
green "2: Добавить дополнительные порты Tuic5"
green "3: Сбросить/удалить дополнительные порты Tuic5"
green "0: Вернуться назад"
readp "Пожалуйста, выберите [0-3]:" menu
if [ "$menu" = "1" ]; then
if [ -n $tu5_ports ]; then
tu5deports
tu5port
echo $sbfiles | xargs -n1 sed -i "89s/$tu5_port/$port_tu/"
restartsb
result_vl_vm_hy_tu && restu5 && sb_client
else
tu5port
echo $sbfiles | xargs -n1 sed -i "89s/$tu5_port/$port_tu/"
restartsb
result_vl_vm_hy_tu && restu5 && sb_client
fi
elif [ "$menu" = "2" ]; then
green "1: Добавить диапазон портов Tuic5"
green "2: Добавить одиночный порт Tuic5"
green "0: Вернуться назад"
readp "Пожалуйста, выберите [0-2]:" menu
if [ "$menu" = "1" ]; then
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
fports && result_vl_vm_hy_tu && sb_client && changeport
elif [ "$menu" = "2" ]; then
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
fport && result_vl_vm_hy_tu && sb_client && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n $tu5_ports ]; then
tu5deports && result_vl_vm_hy_tu && sb_client && changeport
else
yellow "Дополнительные порты для Tuic5 не установлены" && changeport
fi
else
changeport
fi
else
sb
fi
}

changeuuid(){
echo
olduuid=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')
oldvmpath=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')
green "Текущий UUID (пароль) для всех протоколов: $olduuid"
green "Путь Vmess (path): $oldvmpath"
echo
yellow "1: Настроить свой UUID (пароль) для всех протоколов"
yellow "2: Настроить свой путь Vmess (path)"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-2]:" menu
if [ "$menu" = "1" ]; then
readp "Введите UUID (в формате UUID) или нажмите Enter для случайной генерации:" menu
if [ -z "$menu" ]; then
uuid=$(/etc/s-box/sing-box generate uuid)
else
uuid=$menu
fi
echo $sbfiles | xargs -n1 sed -i "s/$olduuid/$uuid/g"
restartsb
blue "Подтвержденный UUID (пароль): ${uuid}" 
blue "Подтвержденный путь Vmess (path): $(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')"
elif [ "$menu" = "2" ]; then
readp "Введите новый путь Vmess (path) или Enter, чтобы оставить без изменений:" menu
if [ -z "$menu" ]; then
echo
else
vmpath=$menu
echo $sbfiles | xargs -n1 sed -i "50s#$oldvmpath#$vmpath#g"
restartsb
fi
blue "Подтвержденный путь Vmess (path): $(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')"
sbshare
else
changeserv
fi
}

changeip(){
if [[ "$sbnh" == "1.10" ]]; then
v4v6
chip(){
rpip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[0].domain_strategy')
sed -i "111s/$rpip/$rrpip/g" /etc/s-box/sb10.json
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
}
readp "1. Приоритет IPV4\n2. Приоритет IPV6\n3. Только IPV4\n4. Только IPV6\nВыберите вариант:" choose
if [[ $choose == "1" && -n $v4 ]]; then
rrpip="prefer_ipv4" && chip && v4_6="Приоритет IPV4 ($v4)"
elif [[ $choose == "2" && -n $v6 ]]; then
rrpip="prefer_ipv6" && chip && v4_6="Приоритет IPV6 ($v6)"
elif [[ $choose == "3" && -n $v4 ]]; then
rrpip="ipv4_only" && chip && v4_6="Только IPV4 ($v4)"
elif [[ $choose == "4" && -n $v6 ]]; then
rrpip="ipv6_only" && chip && v4_6="Только IPV6 ($v6)"
else 
red "Выбранный тип адреса отсутствует на сервере или допущена ошибка ввода" && changeip
fi
blue "Приоритет IP изменен на: ${v4_6}" && sb
else
red "Функция доступна только для ядра версии 1.10.7" && exit
fi
}

tgsbshow(){
echo
yellow "1: Установить/сбросить токен бота и ID пользователя Telegram"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-1]:" menu
if [ "$menu" = "1" ]; then
rm -rf /etc/s-box/sbtg.sh
readp "Введите токен бота Telegram: " token
telegram_token=$token
readp "Введите ваш ID пользователя Telegram: " userid
telegram_id=$userid
echo '#!/bin/bash
export LANG=en_US.UTF-8
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
total_lines=$(wc -l < /etc/s-box/clash_meta_client.yaml)
half=$((total_lines / 2))
head -n $half /etc/s-box/clash_meta_client.yaml > /etc/s-box/clash_meta_client1.txt
tail -n +$((half + 1)) /etc/s-box/clash_meta_client.yaml > /etc/s-box/clash_meta_client2.txt

total_lines=$(wc -l < /etc/s-box/sing_box_client.json)
quarter=$((total_lines / 4))
head -n $quarter /etc/s-box/sing_box_client.json > /etc/s-box/sing_box_client1.txt
tail -n +$((quarter + 1)) /etc/s-box/sing_box_client.json | head -n $quarter > /etc/s-box/sing_box_client2.txt
tail -n +$((2 * quarter + 1)) /etc/s-box/sing_box_client.json | head -n $quarter > /etc/s-box/sing_box_client3.txt
tail -n +$((3 * quarter + 1)) /etc/s-box/sing_box_client.json > /etc/s-box/sing_box_client4.txt

m1=$(cat /etc/s-box/vl_reality.txt 2>/dev/null)
m2=$(cat /etc/s-box/vm_ws.txt 2>/dev/null)
m3=$(cat /etc/s-box/vm_ws_argols.txt 2>/dev/null)
m3_5=$(cat /etc/s-box/vm_ws_argogd.txt 2>/dev/null)
m4=$(cat /etc/s-box/vm_ws_tls.txt 2>/dev/null)
m5=$(cat /etc/s-box/hy2.txt 2>/dev/null)
m6=$(cat /etc/s-box/tuic5.txt 2>/dev/null)
m7=$(cat /etc/s-box/sing_box_client1.txt 2>/dev/null)
m7_5=$(cat /etc/s-box/sing_box_client2.txt 2>/dev/null)
m7_5_5=$(cat /etc/s-box/sing_box_client3.txt 2>/dev/null)
m7_5_5_5=$(cat /etc/s-box/sing_box_client4.txt 2>/dev/null)
m8=$(cat /etc/s-box/clash_meta_client1.txt 2>/dev/null)
m8_5=$(cat /etc/s-box/clash_meta_client2.txt 2>/dev/null)
m9=$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)
m10=$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)
m11=$(cat /etc/s-box/jh_sub.txt 2>/dev/null)
m12=$(cat /etc/s-box/an.txt 2>/dev/null)
message_text_m1=$(echo "$m1")
message_text_m2=$(echo "$m2")
message_text_m3=$(echo "$m3")
message_text_m3_5=$(echo "$m3_5")
message_text_m4=$(echo "$m4")
message_text_m5=$(echo "$m5")
message_text_m6=$(echo "$m6")
message_text_m7=$(echo "$m7")
message_text_m7_5=$(echo "$m7_5")
message_text_m7_5_5=$(echo "$m7_5_5")
message_text_m7_5_5_5=$(echo "$m7_5_5_5")
message_text_m8=$(echo "$m8")
message_text_m8_5=$(echo "$m8_5")
message_text_m9=$(echo "$m9")
message_text_m10=$(echo "$m10")
message_text_m11=$(echo "$m11")
message_text_m12=$(echo "$m12")
MODE=HTML
URL="https://api.telegram.org/bottelegram_token/sendMessage"
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка Vless-reality-vision 】: (v2rayng, nekobox) "$'"'"'\n\n'"'"'"${message_text_m1}")
if [[ -f /etc/s-box/vm_ws.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка Vmess-ws 】: (v2rayng, nekobox) "$'"'"'\n\n'"'"'"${message_text_m2}")
fi
if [[ -f /etc/s-box/vm_ws_argols.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка Vmess-ws(tls)+Argo (врем.) 】: (v2rayng, nekobox) "$'"'"'\n\n'"'"'"${message_text_m3}")
fi
if [[ -f /etc/s-box/vm_ws_argogd.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка Vmess-ws(tls)+Argo (пост.) 】: (v2rayng, nekobox) "$'"'"'\n\n'"'"'"${message_text_m3_5}")
fi
if [[ -f /etc/s-box/vm_ws_tls.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка Vmess-ws-tls 】: (v2rayng, nekobox) "$'"'"'\n\n'"'"'"${message_text_m4}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка Hysteria-2 】: (v2rayng, nekobox) "$'"'"'\n\n'"'"'"${message_text_m5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка Tuic-v5 】: (nekobox) "$'"'"'\n\n'"'"'"${message_text_m6}")
if [[ "$sbnh" != "1.10" ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка Anytls 】: (только новые ядра) "$'"'"'\n\n'"'"'"${message_text_m12}")
fi
if [[ -f /etc/s-box/sing_box_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Подписка Sing-box 】: (SFA, SFW, SFI) "$'"'"'\n\n'"'"'"${message_text_m9}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Конфиг Sing-box (4 части) 】: (SFA, SFW, SFI) "$'"'"'\n\n'"'"'"${message_text_m7}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5_5}")
fi

if [[ -f /etc/s-box/clash_meta_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Подписка Mihomo 】: (клиенты Mihomo) "$'"'"'\n\n'"'"'"${message_text_m10}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Конфиг Mihomo (2 части) 】: (клиенты Mihomo) "$'"'"'\n\n'"'"'"${message_text_m8}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m8_5}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Агрегатор узлов 】: (nekobox) "$'"'"'\n\n'"'"'"${message_text_m11}")

if [ $? == 124 ];then
echo "Тайм-аут запроса TG API, проверьте сеть и доступ к Telegram"
fi
resSuccess=$(echo "$res" | jq -r ".ok")
if [[ $resSuccess = "true" ]]; then
echo "Уведомление в TG успешно отправлено";
else
echo "Ошибка отправки в TG, проверьте токен бота и ID пользователя";
fi
' > /etc/s-box/sbtg.sh
sed -i "s/telegram_token/$telegram_token/g" /etc/s-box/sbtg.sh
sed -i "s/telegram_id/$telegram_id/g" /etc/s-box/sbtg.sh
green "Настройка завершена! Убедитесь, что бот активирован!"
tgnotice
else
changeserv
fi
}

tgnotice(){
if [[ -f /etc/s-box/sbtg.sh ]]; then
green "Пожалуйста, подождите 5 секунд, бот отправляет уведомление..."
sbshare > /dev/null 2>&1
bash /etc/s-box/sbtg.sh
else
yellow "Функция уведомлений в TG не настроена"
fi
exit
}

changeserv(){
sbactive
echo
green "Варианты изменения конфигурации Sing-box:"
readp "1: Смена домена Reality, переключение сертификатов, вкл/выкл TLS\n2: Смена UUID (пароля) всех протоколов, пути Vmess\n3: Настройка туннелей Argo (временный/постоянный)\n4: Смена приоритета IPV4/IPV6 (только для ядра 1.10.7)\n5: Настройка уведомлений в Telegram\n6: Смена аккаунта выхода Warp-wireguard\n7: Настройка подписки через GitLab\n8: Настройка оптимизации CDN для всех узлов Vmess\n0: Вернуться назад\nПожалуйста, выберите [0-8]:" menu
if [ "$menu" = "1" ];then
changeym
elif [ "$menu" = "2" ];then
changeuuid
elif [ "$menu" = "3" ];then
cfargo_ym
elif [ "$menu" = "4" ];then
changeip
elif [ "$menu" = "5" ];then
tgsbshow
elif [ "$menu" = "6" ];then
changewg
elif [ "$menu" = "7" ];then
gitlabsub
elif [ "$menu" = "8" ];then
vmesscfadd
else 
sb
fi
}

vmesscfadd(){
echo
green "Рекомендуется использовать стабильные домены крупных компаний для оптимизации CDN:"
blue "www.visa.com.sg"
blue "www.wto.org"
blue "www.web.com"
blue "yg1.ygkkk.dpdns.org (замените 1 на любое число 1-11)"
echo
yellow "1: Указать CDN-адрес для основного узла Vmess-ws(tls)"
yellow "2: Сбросить host/sni для варианта 1 (домен, направленный на CF)"
yellow "3: Указать CDN-адрес для узла Vmess-ws(tls)-Argo"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-3]:" menu
if [ "$menu" = "1" ]; then
echo
green "Убедитесь, что IP вашего VPS направлен на домен в Cloudflare"
if [[ ! -f /etc/s-box/cfymjx.txt ]] 2>/dev/null; then
readp "Введите host/sni клиента (домен, привязанный к IP через CF):" menu
echo "$menu" > /etc/s-box/cfymjx.txt
fi
echo
readp "Введите кастомный оптимизированный IP или домен:" menu
echo "$menu" > /etc/s-box/cfvmadd_local.txt
green "Настройка успешна, выберите пункт 9 в главном меню для обновления" && sleep 2 && vmesscfadd
elif  [ "$menu" = "2" ]; then
rm -rf /etc/s-box/cfymjx.txt
green "Сброс успешен, можно настроить заново через пункт 1" && sleep 2 && vmesscfadd
elif  [ "$menu" = "3" ]; then
readp "Введите кастомный оптимизированный IP или домен для Argo:" menu
echo "$menu" > /etc/s-box/cfvmadd_argo.txt
green "Настройка успешна, выберите пункт 9 в главном меню для обновления" && sleep 2 && vmesscfadd
else
changeserv
fi
}

gitlabsub(){
echo
green "Убедитесь, что проект на GitLab создан, функция Push включена и получен токен доступа"
yellow "1: Настроить/сбросить подписку GitLab"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-1]:" menu
if [ "$menu" = "1" ]; then
cd /etc/s-box
readp "Введите почту (email): " email
readp "Введите токен доступа (access token): " token
readp "Введите имя пользователя: " userid
readp "Введите название проекта: " project
echo
green "Для нескольких VPS можно использовать один токен и проект, создавая ссылки для разных веток"
green "Нажмите Enter, чтобы использовать основную ветку (main) — рекомендуется для первой VPS"
readp "Название новой ветки (branch): " gitlabml
echo
if [[ -z "$gitlabml" ]]; then
gitlab_ml=''
git_sk=main
rm -rf /etc/s-box/gitlab_ml_ml
else
gitlab_ml=":${gitlabml}"
git_sk="${gitlabml}"
echo "${gitlab_ml}" > /etc/s-box/gitlab_ml_ml
fi
echo "$token" > /etc/s-box/gitlabtoken.txt
rm -rf /etc/s-box/.git
git init >/dev/null 2>&1
git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git config --global user.email "${email}" >/dev/null 2>&1
git config --global user.name "${userid}" >/dev/null 2>&1
git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
branches=$(git branch)
if [[ $branches == *master* ]]; then
git branch -m master main >/dev/null 2>&1
fi
git remote add origin https://${token}@gitlab.com/${userid}/${project}.git >/dev/null 2>&1
if [[ $(ls -a | grep '^\.git$') ]]; then
cat > /etc/s-box/gitpush.sh <<EOF
#!/usr/bin/expect
spawn bash -c "git push -f origin main${gitlab_ml}"
expect "Password for 'https://$(cat /etc/s-box/gitlabtoken.txt 2>/dev/null)@gitlab.com':"
send "$(cat /etc/s-box/gitlabtoken.txt 2>/dev/null)\r"
interact
EOF
chmod +x gitpush.sh
./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/s-box/gitlabtoken.txt >/dev/null 2>&1
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/sing_box_client.json/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/sing_box_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/clash_meta_client.yaml/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/clash_meta_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh_sub.txt/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/jh_sub_gitlab.txt
clsbshow
else
yellow "Не удалось установить ссылку подписки GitLab, пожалуйста, сообщите об ошибке"
fi
cd
else
changeserv
fi
}

gitlabsubgo(){
cd /etc/s-box
if [[ $(ls -a | grep '^\.git$') ]]; then
if [ -f /etc/s-box/gitlab_ml_ml ]; then
gitlab_ml=$(cat /etc/s-box/gitlab_ml_ml)
fi
git rm --cached sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git commit -m "commit_rm_$(date +"%F %T")" >/dev/null 2>&1
git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
chmod +x gitpush.sh
./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/s-box/gitlabtoken.txt >/dev/null 2>&1
clsbshow
else
yellow "Ссылка подписки GitLab не настроена"
fi
cd
}

clsbshow(){
green "Узлы Sing-box обновлены и отправлены"
green "Ссылка подписки Sing-box:"
blue "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
green "QR-код подписки Sing-box:"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "Конфигурация узлов Mihomo обновлена и отправлена"
green "Ссылка подписки Mihomo:"
blue "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
green "QR-код подписки Mihomo:"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "Конфигурация агрегированных узлов обновлена и отправлена"
green "Ссылка подписки:"
blue "$(cat /etc/s-box/jh_sub_gitlab.txt 2>/dev/null)"
echo
yellow "Вы можете ввести ссылку подписки в браузере, чтобы просмотреть содержимое. Если данных нет, проверьте настройки GitLab и выполните сброс"
echo
}

warpwg(){
warpcode(){
reg(){
keypair=$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout)
private_key=$(echo "$keypair" | awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' | tr -d '[:space:]' | xxd -r -p | base64)
public_key=$(echo "$keypair" | awk '/pub:/{flag=1} flag' | tr -d '[:space:]' | xxd -r -p | base64)
response=$(curl -sL --tlsv1.3 --connect-timeout 3 --max-time 5 \
-X POST 'https://api.cloudflareclient.com/v0a2158/reg' \
-H 'CF-Client-Version: a-7.21-0721' \
-H 'Content-Type: application/json' \
-d '{
"key": "'"$public_key"'",
"tos": "'"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')"'"
}')
if [ -z "$response" ]; then
return 1
fi
echo "$response" | python3 -m json.tool 2>/dev/null | sed "/\"account_type\"/i\         \"private_key\": \"$private_key\","
}
reserved(){
reserved_str=$(echo "$warp_info" | grep 'client_id' | cut -d\" -f4)
reserved_hex=$(echo "$reserved_str" | base64 -d | xxd -p)
reserved_dec=$(echo "$reserved_hex" | fold -w2 | while read HEX; do printf '%d ' "0x${HEX}"; done | awk '{print "["$1", "$2", "$3"]"}')
echo -e "{\n    \"reserved_dec\": $reserved_dec,"
echo -e "    \"reserved_hex\": \"0x$reserved_hex\","
echo -e "    \"reserved_str\": \"$reserved_str\"\n}"
}
result() {
echo "$warp_reserved" | grep -P "reserved" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/:\[/: \[/g' | sed 's/\([0-9]\+\),\([0-9]\+\),\([0-9]\+\)/\1, \2, \3/' | sed 's/^"/    "/g' | sed 's/"$/",/g'
echo "$warp_info" | grep -P "(private_key|public_key|\"v4\": \"172.16.0.2\"|\"v6\": \"2)" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/^"/    "/g'
echo "}"
}
warp_info=$(reg) 
warp_reserved=$(reserved) 
result
}
output=$(warpcode)
if ! echo "$output" 2>/dev/null | grep -w "private_key" > /dev/null; then
v6=2606:4700:110:860e:738f:b37:f15:d38d
pvk=g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4=
res=[33,217,129]
else
pvk=$(echo "$output" | sed -n 4p | awk '{print $2}' | tr -d ' "' | sed 's/.$//')
v6=$(echo "$output" | sed -n 7p | awk '{print $2}' | tr -d ' "')
res=$(echo "$output" | sed -n 1p | awk -F":" '{print $NF}' | tr -d ' ' | sed 's/.$//')
fi
blue "Закрытый ключ Private_key: $pvk"
blue "Адрес IPv6: $v6"
blue "Значение reserved: $res"
}

changewg(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
if [[ "$sbnh" == "1.10" ]]; then
wgipv6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .local_address[1] | split("/")[0]')
wgprkey=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .private_key')
wgres=$(sed -n '165s/.*\[\(.*\)\].*/\1/p' /etc/s-box/sb.json)
wgip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .server')
wgpo=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .server_port')
else
wgipv6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .address[1] | split("/")[0]')
wgprkey=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .private_key')
wgres=$(sed -n '142s/.*\[\(.*\)\].*/\1/p' /etc/s-box/sb.json)
wgip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .peers[].address')
wgpo=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .peers[].port')
fi
echo
green "Текущие параметры warp-wireguard, доступные для замены:"
green "Закрытый ключ Private_key: $wgprkey"
green "Адрес IPv6: $wgipv6"
green "Значение Reserved: $wgres"
green "IP удаленной стороны: $wgip:$wgpo"
echo
yellow "1: Сменить аккаунт warp-wireguard"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-1]:" menu
if [ "$menu" = "1" ]; then
green "Новый случайно сгенерированный обычный аккаунт warp-wireguard:"
warpwg
echo
readp "Введите свой Private_key:" menu
sed -i "163s#$wgprkey#$menu#g" /etc/s-box/sb10.json
sed -i "132s#$wgprkey#$menu#g" /etc/s-box/sb11.json
readp "Введите свой адрес IPv6:" menu
sed -i "161s/$wgipv6/$menu/g" /etc/s-box/sb10.json
sed -i "130s/$wgipv6/$menu/g" /etc/s-box/sb11.json
readp "Введите свое значение Reserved (формат: число,число,число), если нет — нажмите Enter:" menu
if [ -z "$menu" ]; then
menu=0,0,0
fi
sed -i "165s/$wgres/$menu/g" /etc/s-box/sb10.json
sed -i "142s/$wgres/$menu/g" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
green "Настройка завершена"
else
changeserv
fi
}

sbymfl(){
sbport=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}' | awk -F":" '{print $NF}') 
sbport=${sbport:-'40000'}
resv1=$(curl -sm3 --socks5 localhost:$sbport icanhazip.com)
resv2=$(curl -sm3 -x socks5h://localhost:$sbport icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
warp_s4_ip='Socks5-IPv4 не запущен, режим черного списка'
warp_s6_ip='Socks5-IPv6 не запущен, режим черного списка'
else
warp_s4_ip='Socks5-IPv4 доступен'
warp_s6_ip='Socks5-IPv6 (тест)'
fi
v4v6
if [[ -z $v4 ]]; then
vps_ipv4='Локальный IPv4 отсутствует, режим черного списка'      
vps_ipv6="Текущий IP: $v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="Текущий IP: $v4"    
vps_ipv6="Текущий IP: $v6"
else
vps_ipv4="Текущий IP: $v4"    
vps_ipv6='Локальный IPv6 отсутствует, режим черного списка'
fi
unset swg4 swd4 swd6 swg6 ssd4 ssg4 ssd6 ssg6 sad4 sag4 sad6 sag6
wd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].domain_suffix | join(" ")')
wg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].geosite | join(" ")' 2>/dev/null)
if [[ "$wd4" == "yg_kkk" && ("$wg4" == "yg_kkk" || -z "$wg4") ]]; then
wfl4="${yellow}【Warp выход IPv4 доступен】Маршрутизация не настроена${plain}"
else
if [[ "$wd4" != "yg_kkk" ]]; then
swd4="$wd4 "
fi
if [[ "$wg4" != "yg_kkk" ]]; then
swg4=$wg4
fi
wfl4="${yellow}【Warp выход IPv4 доступен】Маршрутизация: $swd4$swg4${plain} "
fi

wd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].domain_suffix | join(" ")')
wg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].geosite | join(" ")' 2>/dev/null)
if [[ "$wd6" == "yg_kkk" && ("$wg6" == "yg_kkk"|| -z "$wg6") ]]; then
wfl6="${yellow}【Warp выход IPv6 (тест)】Маршрутизация не настроена${plain}"
else
if [[ "$wd6" != "yg_kkk" ]]; then
swd6="$wd6 "
fi
if [[ "$wg6" != "yg_kkk" ]]; then
swg6=$wg6
fi
wfl6="${yellow}【Warp выход IPv6 (тест)】Маршрутизация: $swd6$swg6${plain} "
fi

sd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].domain_suffix | join(" ")')
sg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].geosite | join(" ")' 2>/dev/null)
if [[ "$sd4" == "yg_kkk" && ("$sg4" == "yg_kkk" || -z "$sg4") ]]; then
sfl4="${yellow}【$warp_s4_ip】Маршрутизация не настроена${plain}"
else
if [[ "$sd4" != "yg_kkk" ]]; then
ssd4="$sd4 "
fi
if [[ "$sg4" != "yg_kkk" ]]; then
ssg4=$sg4
fi
sfl4="${yellow}【$warp_s4_ip】Маршрутизация: $ssd4$ssg4${plain} "
fi

sd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].domain_suffix | join(" ")')
sg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].geosite | join(" ")' 2>/dev/null)
if [[ "$sd6" == "yg_kkk" && ("$sg6" == "yg_kkk" || -z "$sg6") ]]; then
sfl6="${yellow}【$warp_s6_ip】Маршрутизация не настроена${plain}"
else
if [[ "$sd6" != "yg_kkk" ]]; then
ssd6="$sd6 "
fi
if [[ "$sg6" != "yg_kkk" ]]; then
ssg6=$sg6
fi
sfl6="${yellow}【$warp_s6_ip】Маршрутизация: $ssd6$ssg6${plain} "
fi

ad4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].domain_suffix | join(" ")' 2>/dev/null)
ag4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].geosite | join(" ")' 2>/dev/null)
if [[ ("$ad4" == "yg_kkk" || -z "$ad4") && ("$ag4" == "yg_kkk" || -z "$ag4") ]]; then
adfl4="${yellow}【$vps_ipv4】Маршрутизация не настроена${plain}" 
else
if [[ "$ad4" != "yg_kkk" ]]; then
sad4="$ad4 "
fi
if [[ "$ag4" != "yg_kkk" ]]; then
sag4=$ag4
fi
adfl4="${yellow}【$vps_ipv4】Маршрутизация: $sad4$sag4${plain} "
fi

ad6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].domain_suffix | join(" ")' 2>/dev/null)
ag6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].geosite | join(" ")' 2>/dev/null)
if [[ ("$ad6" == "yg_kkk" || -z "$ad6") && ("$ag6" == "yg_kkk" || -z "$ag6") ]]; then
adfl6="${yellow}【$vps_ipv6】Маршрутизация не настроена${plain}" 
else
if [[ "$ad6" != "yg_kkk" ]]; then
sad6="$ad6 "
fi
if [[ "$ag6" != "yg_kkk" ]]; then
sag6=$ag6
fi
adfl6="${yellow}【$vps_ipv6】Маршрутизация: $sad6$sag6${plain} "
fi
}

changefl(){
sbactive
blue "Настройка единой маршрутизации по доменам для всех протоколов"
blue "Для обеспечения работы маршрутизации используется приоритетный режим Dual Stack (IPv4/IPv6)"
blue "Warp-wireguard включен по умолчанию (опции 1 и 2)"
blue "Для Socks5 требуется установка официального клиента Warp или WARP-plus-Socks5-Psiphon (опции 3 и 4)"
blue "Локальная маршрутизация VPS (опции 5 и 6)"
echo
[[ "$sbnh" == "1.10" ]] && blue "Текущее ядро Sing-box поддерживает маршрутизацию geosite" || blue "Текущее ядро Sing-box не поддерживает geosite, доступны только опции 2, 3, 5, 6"
echo
yellow "Внимание:"
yellow "1. В режиме полного домена вводите только полные адреса (напр., www.google.com)"
yellow "2. В режиме geosite вводите имена правил (напр., netflix, disney, openai; для обхода Китая: geolocation-!cn)"
yellow "3. Не дублируйте маршрутизацию для одного и того же домена или geosite"
yellow "4. Если в канале нет сети, маршрутизация работает как черный список (доступ будет заблокирован)"
changef
}

changef(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sbymfl
echo
[[ "$sbnh" != "1.10" ]] && wfl4='Не поддерживается' sfl6='Не поддерживается' adfl4='Не поддерживается' adfl6='Не поддерживается'
green "1: Сбросить домены с приоритетом Warp-wireguard-IPv4 $wfl4"
green "2: Сбросить домены с приоритетом Warp-wireguard-IPv6 $wfl6"
green "3: Сбросить домены с приоритетом Warp-Socks5-IPv4 $sfl4"
green "4: Сбросить домены с приоритетом Warp-Socks5-IPv6 $sfl6"
green "5: Сбросить домены с локальным приоритетом IPv4 VPS $adfl4"
green "6: Сбросить домены с локальным приоритетом IPv6 VPS $adfl6"
green "0: Вернуться назад"
echo
readp "Пожалуйста, выберите:" menu

if [ "$menu" = "1" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1: Режим полного домена\n2: Режим geosite\n3: Вернуться назад\nПожалуйста, выберите:" menu
if [ "$menu" = "1" ]; then
readp "Разделяйте домены пробелом (Enter для сброса канала Warp-wireguard-IPv4):" w4flym
if [ -z "$w4flym" ]; then
w4flym='"yg_kkk"'
else
w4flym="$(echo "$w4flym" | sed 's/ /","/g')"
w4flym="\"$w4flym\""
fi
sed -i "184s/.*/$w4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "Разделяйте имена geosite пробелом (Enter для сброса канала Warp-wireguard-IPv4):" w4flym
if [ -z "$w4flym" ]; then
w4flym='"yg_kkk"'
else
w4flym="$(echo "$w4flym" | sed 's/ /","/g')"
w4flym="\"$w4flym\""
fi
sed -i "187s/.*/$w4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
changef
fi
else
yellow "К сожалению, сейчас поддерживается только Warp-wireguard-IPv6. Для IPv4 используйте ядро версии 1.10" && exit
fi

elif [ "$menu" = "2" ]; then
readp "1: Режим полного домена\n2: Режим geosite\n3: Вернуться назад\nПожалуйста, выберите:" menu
if [ "$menu" = "1" ]; then
readp "Разделяйте домены пробелом (Enter для сброса канала Warp-wireguard-IPv6):" w6flym
if [ -z "$w6flym" ]; then
w6flym='"yg_kkk"'
else
w6flym="$(echo "$w6flym" | sed 's/ /","/g')"
w6flym="\"$w6flym\""
fi
sed -i "193s/.*/$w6flym/" /etc/s-box/sb10.json
sed -i "184s/.*/$w6flym/" /etc/s-box/sb11.json
sed -i "196s/.*/$w6flym/" /etc/s-box/sb11.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "Разделяйте имена geosite пробелом (Enter для сброса канала Warp-wireguard-IPv6):" w6flym
if [ -z "$w6flym" ]; then
w6flym='"yg_kkk"'
else
w6flym="$(echo "$w6flym" | sed 's/ /","/g')"
w6flym="\"$w6flym\""
fi
sed -i "196s/.*/$w6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "К сожалению, текущее ядро Sing-box не поддерживает geosite. Для поддержки используйте ядро версии 1.10" && exit
fi
else
changef
fi

elif [ "$menu" = "3" ]; then
readp "1: Режим полного домена\n2: Режим geosite\n3: Вернуться назад\nПожалуйста, выберите:" menu
if [ "$menu" = "1" ]; then
readp "Разделяйте домены пробелом (Enter для сброса канала Warp-Socks5-IPv4):" s4flym
if [ -z "$s4flym" ]; then
s4flym='"yg_kkk"'
else
s4flym="$(echo "$s4flym" | sed 's/ /","/g')"
s4flym="\"$s4flym\""
fi
sed -i "202s/.*/$s4flym/" /etc/s-box/sb10.json
sed -i "177s/.*/$s4flym/" /etc/s-box/sb11.json
sed -i "190s/.*/$s4flym/" /etc/s-box/sb11.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "Разделяйте имена geosite пробелом (Enter для сброса канала Warp-Socks5-IPv4):" s4flym
if [ -z "$s4flym" ]; then
s4flym='"yg_kkk"'
else
s4flym="$(echo "$s4flym" | sed 's/ /","/g')"
s4flym="\"$s4flym\""
fi
sed -i "205s/.*/$s4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "К сожалению, текущее ядро Sing-box не поддерживает geosite. Для поддержки используйте ядро версии 1.10" && exit
fi
else
changef
fi

elif [ "$menu" = "4" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1: Режим полного домена\n2: Режим geosite\n3: Вернуться назад\nПожалуйста, выберите:" menu
if [ "$menu" = "1" ]; then
readp "Разделяйте домены пробелом (Enter для сброса канала Warp-Socks5-IPv6):" s6flym
if [ -z "$s6flym" ]; then
s6flym='"yg_kkk"'
else
s6flym="$(echo "$s6flym" | sed 's/ /","/g')"
s6flym="\"$s6flym\""
fi
sed -i "211s/.*/$s6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "Разделяйте имена geosite пробелом (Enter для сброса канала Warp-Socks5-IPv6):" s6flym
if [ -z "$s6flym" ]; then
s6flym='"yg_kkk"'
else
s6flym="$(echo "$s6flym" | sed 's/ /","/g')"
s6flym="\"$s6flym\""
fi
sed -i "214s/.*/$s6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
changef
fi
else
yellow "К сожалению, сейчас поддерживается только Warp-Socks5-IPv4. Для IPv6 используйте ядро версии 1.10" && exit
fi

elif [ "$menu" = "5" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1: Режим полного домена\n2: Режим geosite\n3: Вернуться назад\nПожалуйста, выберите:" menu
if [ "$menu" = "1" ]; then
readp "Разделяйте домены пробелом (Enter для сброса локального канала IPv4):" ad4flym
if [ -z "$ad4flym" ]; then
ad4flym='"yg_kkk"'
else
ad4flym="$(echo "$ad4flym" | sed 's/ /","/g')"
ad4flym="\"$ad4flym\""
fi
sed -i "220s/.*/$ad4flym/" /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "Разделяйте имена geosite пробелом (Enter для сброса локального канала IPv4):" ad4flym
if [ -z "$ad4flym" ]; then
ad4flym='"yg_kkk"'
else
ad4flym="$(echo "$ad4flym" | sed 's/ /","/g')"
ad4flym="\"$ad4flym\""
fi
sed -i "223s/.*/$ad4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "К сожалению, текущее ядро Sing-box не поддерживает geosite. Для поддержки используйте ядро версии 1.10" && exit
fi
else
changef
fi
else
yellow "К сожалению, для локальной маршрутизации IPv4 используйте ядро версии 1.10" && exit
fi

elif [ "$menu" = "6" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1: Режим полного домена\n2: Режим geosite\n3: Вернуться назад\nПожалуйста, выберите:" menu
if [ "$menu" = "1" ]; then
readp "Разделяйте домены пробелом (Enter для сброса локального канала IPv6):" ad6flym
if [ -z "$ad6flym" ]; then
ad6flym='"yg_kkk"'
else
ad6flym="$(echo "$ad6flym" | sed 's/ /","/g')"
ad6flym="\"$ad6flym\""
fi
sed -i "229s/.*/$ad6flym/" /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "Разделяйте имена geosite пробелом (Enter для сброса локального канала IPv6):" ad6flym
if [ -z "$ad6flym" ]; then
ad6flym='"yg_kkk"'
else
ad6flym="$(echo "$ad6flym" | sed 's/ /","/g')"
ad6flym="\"$ad6flym\""
fi
sed -i "232s/.*/$ad6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "К сожалению, текущее ядро Sing-box не поддерживает geosite. Для поддержки используйте ядро версии 1.10" && exit
fi
else
changef
fi
else
yellow "К сожалению, для локальной маршрутизации IPv6 используйте ядро версии 1.10" && exit
fi
else
sb
fi
}

restartsb(){
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box restart
else
systemctl enable sing-box
systemctl start sing-box
systemctl restart sing-box
fi
}

stclre(){
if [[ ! -f '/etc/s-box/sb.json' ]]; then
red "Sing-box установлен некорректно" && exit
fi
readp "1: Перезапустить\n2: Остановить\nПожалуйста, выберите:" menu
if [ "$menu" = "1" ]; then
restartsb
sbactive
green "Служба Sing-box перезапущена\n" && sleep 3 && sb
elif [ "$menu" = "2" ]; then
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box stop
else
systemctl stop sing-box
systemctl disable sing-box
fi
green "Служба Sing-box остановлена\n" && sleep 3 && sb
else
stclre
fi
}

cronsb(){
uncronsb
crontab -l 2>/dev/null > /tmp/crontab.tmp
echo "0 1 * * * systemctl restart sing-box;rc-service sing-box restart" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
}
uncronsb(){
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sing-box/d' /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
}

lnsb(){
rm -rf /usr/bin/sb
curl -L -o /usr/bin/sb -# --retry 2 --insecure https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh
chmod +x /usr/bin/sb
}

upsbyg(){
if [[ ! -f '/usr/bin/sb' ]]; then
red "Скрипт Sing-box-yg не установлен" && exit
fi
lnsb
curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
green "Скрипт установки Sing-box-yg успешно обновлен" && sleep 5 && sb
}

lapre(){
latcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
precore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]*-[^"]*"' | sed -n 1p | tr -d '",')
inscore=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')
}

upsbcroe(){
sbactive
lapre
[[ $inscore =~ ^[0-9.]+$ ]] && lat="【Установлена v$inscore】" || pre="【Установлена v$inscore】"
green "1: Обновить/сменить на последнюю стабильную версию Sing-box v$latcore  ${bblue}${lat}${plain}"
green "2: Обновить/сменить на последнюю пре-релизную версию Sing-box v$precore  ${bblue}${pre}${plain}"
green "3: Переключиться на конкретную версию (укажите номер, рекомендуется 1.10.0+)"
green "0: Вернуться назад"
readp "Пожалуйста, выберите [0-3]:" menu
if [ "$menu" = "1" ]; then
upcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
elif [ "$menu" = "2" ]; then
upcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]*-[^"]*"' | sed -n 1p | tr -d '",')
elif [ "$menu" = "3" ]; then
echo
red "Внимание: список версий доступен на https://github.com/SagerNet/sing-box/tags (необходима версия 1.10.0+)"
green "Формат стабильной версии: X.X.X (напр. 1.10.7. Серия 1.10 поддерживает geosite, версии выше — нет)"
green "Формат пре-релиза: X.X.X-alpha/rc/beta.X (напр. 1.10.0-rc.1)"
readp "Введите номер версии Sing-box:" upcore
else
sb
fi
if [[ -n $upcore ]]; then
green "Начинаю загрузку и обновление ядра Sing-box... пожалуйста, подождите"
sbname="sing-box-$upcore-linux-$cpu"
curl -L -o /etc/s-box/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$upcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
blue "Версия ядра Sing-box успешно изменена на: $(/etc/s-box/sing-box version | awk '/version/{print $NF}')" && sleep 3 && sb
else
red "Ядро Sing-box скачано не полностью, установка не удалась, попробуйте снова" && upsbcroe
fi
else
red "Ошибка загрузки ядра Sing-box или версия не найдена, попробуйте снова" && upsbcroe
fi
else
red "Ошибка определения версии, попробуйте снова" && upsbcroe
fi
}

unins(){
if [[ x"${release}" == x"alpine" ]]; then
for svc in sing-box argo; do
rc-service "$svc" stop >/dev/null 2>&1
rc-update del "$svc" default >/dev/null 2>&1
done
rm -rf /etc/init.d/{sing-box,argo}
else
for svc in sing-box argo; do
systemctl stop "$svc" >/dev/null 2>&1
systemctl disable "$svc" >/dev/null 2>&1
done
rm -rf /etc/systemd/system/{sing-box.service,argo.service}
fi
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box sbyg_update /usr/bin/sb /root/geoip.db /root/geosite.db /root/warpapi /root/warpip
uncronsb
iptables -t nat -F PREROUTING >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
green "Удаление Sing-box завершено!"
blue "Будем рады видеть вас снова! Скрипт: bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)"
echo
}

sblog(){
red "Для выхода из логов нажмите Ctrl+C"
if [[ x"${release}" == x"alpine" ]]; then
yellow "Просмотр логов в Alpine временно не поддерживается"
else
#systemctl status sing-box
journalctl -u sing-box.service -o cat -f
fi
}

sbactive(){
if [[ ! -f /etc/s-box/sb.json ]]; then
red "Sing-box запущен некорректно. Переустановите его или выберите пункт 10 для просмотра логов" && exit
fi
}

sbshare(){
rm -rf /etc/s-box/{jhdy,vl_reality,vm_ws_argols,vm_ws_argogd,vm_ws,vm_ws_tls,hy2,tuic5,an}.txt
result_vl_vm_hy_tu && resvless && resvmess && reshy2 && restu5
if [[ "$sbnh" != "1.10" ]]; then
resan
fi
cat /etc/s-box/vl_reality.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_argols.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_argogd.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_tls.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/hy2.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/tuic5.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/an.txt 2>/dev/null >> /etc/s-box/jhdy.txt
v2sub=$(cat /etc/s-box/jhdy.txt 2>/dev/null)
echo "$v2sub" > /etc/s-box/jh_sub.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀 Инфо о узле [ Агрегированный узел ]:" && sleep 2
echo
echo "Ссылки для шеринга:"
echo -e "${yellow}$v2sub${plain}"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
sb_client
}

clash_sb_share(){
sbactive
echo
yellow "1: Обновить и просмотреть ссылки шеринга, QR-коды и агрегированный узел"
yellow "2: Обновить и просмотреть конфиги Mihomo, Sing-box (SFA/SFI/SFW) и приватную подписку Gitlab"
yellow "3: Отправить актуальную конфигурацию (опции 1+2) в Telegram"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-3]:" menu
if [ "$menu" = "1" ]; then
sbshare
elif  [ "$menu" = "2" ]; then
green "Пожалуйста, подождите..."
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "Ссылки подписки Gitlab:"
gitlabsubgo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀 Конфигурация Mihomo:"
red "Файл: /etc/s-box/clash_meta_client.yaml. При ручном создании используйте формат .yaml" && sleep 2
echo
cat /etc/s-box/clash_meta_client.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀 Конфигурация SFA/SFI/SFW:"
red "SFA (Android), SFI (iOS). SFW для Windows скачивайте в GitHub-репозитории автора."
red "Файл: /etc/s-box/sing_box_client.json. При ручном создании используйте формат .json" && sleep 2
echo
cat /etc/s-box/sing_box_client.json
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
elif [ "$menu" = "3" ]; then
tgnotice
else
sb
fi
}

acme(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
bash <(curl -Ls https://raw.githubusercontent.com/MyNicknme/Acme/refs/heads/main/Acme-yonggekkk.sh)
}
cfwarp(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
bash <(curl -Ls https://raw.githubusercontent.com/MyNicknme/warp/refs/heads/main/CFwarp.sh)
}
bbr(){
if [[ $vi =~ lxc|openvz ]]; then
yellow "Архитектура вашего VPS ($vi) не поддерживает включение оригинального BBR" && sleep 2 && exit 
else
green "Нажмите любую клавишу для включения BBR или Ctrl+C для отмены"
bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
fi
}

showprotocol(){
allports
sbymfl
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
argopid
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) || -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
vm_zs="TLS выкл"
argoym="Включено"
else
vm_zs="TLS выкл"
argoym="Отключено"
fi
else
vm_zs="TLS вкл"
argoym="Не поддерживается"
fi
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_zs="Самоподписанный" || hy2_zs="Сертификат домена"
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_zs="Самоподписанный" || tu5_zs="Сертификат домена"
an_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
[[ "$an_sniname" = '/etc/s-box/private.key' ]] && an_zs="Самоподписанный" || an_zs="Сертификат домена"
echo -e "Ключевая информация об узлах Sing-box и маршрутизации:"
echo -e "🚀【 Vless-reality 】${yellow}порт:$vl_port  Reality SNI (маскировка): $(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')${plain}"
if [[ "$tls" = "false" ]]; then
echo -e "🚀【    Vmess-ws    】${yellow}порт:$vm_port   Тип сертификата:$vm_zs   Статус Argo:$argoym${plain}"
else
echo -e "🚀【 Vmess-ws-tls   】${yellow}порт:$vm_port   Тип сертификата:$vm_zs   Статус Argo:$argoym${plain}"
fi
echo -e "🚀【   Hysteria-2   】${yellow}порт:$hy2_port  Тип сертификата:$hy2_zs  Доп. порты: $hy2zfport${plain}"
echo -e "🚀【     Tuic-v5     】${yellow}порт:$tu5_port  Тип сертификата:$tu5_zs  Доп. порты: $tu5zfport${plain}"
if [[ "$sbnh" != "1.10" ]]; then
echo -e "🚀【     Anytls      】${yellow}порт:$an_port  Тип сертификата:$an_zs${plain}"
fi
if [ "$argoym" = "Включено" ]; then
echo -e "Vmess-UUID: ${yellow}$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')${plain}"
echo -e "Vmess-Path: ${yellow}$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')${plain}"
if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
echo -e "Временный домен Argo: ${yellow}$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')${plain}"
fi
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
echo -e "Постоянный домен Argo: ${yellow}$(cat /etc/s-box/sbargoym.log 2>/dev/null)${plain}"
fi
fi
echo "------------------------------------------------------------------------------------"
if [[ -n $(ps -e | grep sbwpph) ]]; then
s5port=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}'| awk -F":" '{print $NF}')
s5gj=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $6}')
case "$s5gj" in
AT) showgj="Австрия" ;;
AU) showgj="Австралия" ;;
BE) showgj="Бельгия" ;;
BG) showgj="Болгария" ;;
CA) showgj="Канада" ;;
CH) showgj="Швейцария" ;;
CZ) showgj="Чехия" ;;
DE) showgj="Германия" ;;
DK) showgj="Дания" ;;
EE) showgj="Эстония" ;;
ES) showgj="Испания" ;;
FI) showgj="Финляндия" ;;
FR) showgj="Франция" ;;
GB) showgj="Великобритания" ;;
HR) showgj="Хорватия" ;;
HU) showgj="Венгрия" ;;
IE) showgj="Ирландия" ;;
IN) showgj="Индия" ;;
IT) showgj="Италия" ;;
JP) showgj="Япония" ;;
LT) showgj="Литва" ;;
LV) showgj="Латвия" ;;
NL) showgj="Нидерланды" ;;
NO) showgj="Норвегия" ;;
PL) showgj="Польша" ;;
PT) showgj="Португалия" ;;
RO) showgj="Румыния" ;;
RS) showgj="Сербия" ;;
SE) showgj="Швеция" ;;
SG) showgj="Сингапур" ;;
SK) showgj="Словакия" ;;
US) showgj="США" ;;
esac
grep -q "country" /etc/s-box/sbwpph.log 2>/dev/null && s5ms="Режим прокси Psiphon (порт:$s5port  страна:$showgj)" || s5ms="Локальный режим прокси Warp (порт:$s5port)"
echo -e "Статус WARP-plus-Socks5: $yellowЗапущено $s5ms$plain"
else
echo -e "Статус WARP-plus-Socks5: $yellowНе запущено$plain"
fi
echo "------------------------------------------------------------------------------------"
ww4="Домены с приоритетом Warp-wireguard-IPv4: $wfl4"
ww6="Домены с приоритетом Warp-wireguard-IPv6: $wfl6"
ws4="Домены с приоритетом Warp-Socks5-IPv4: $sfl4"
ws6="Домены с приоритетом Warp-Socks5-IPv6: $sfl6"
l4="Домены с локальным приоритетом IPv4 VPS: $adfl4"
l6="Домены с локальным приоритетом IPv6 VPS: $adfl6"
[[ "$sbnh" == "1.10" ]] && ymflzu=("ww4" "ww6" "ws4" "ws6" "l4" "l6") || ymflzu=("ww6" "ws4" "l4" "l6")
for ymfl in "${ymflzu[@]}"; do
if [[ ${!ymfl} != *"Не"* ]]; then
echo -e "${!ymfl}"
fi
done
if [[ $ww4 = *"Не"* && $ww6 = *"Не"* && $ws4 = *"Не"* && $ws6 = *"Не"* && $l4 = *"Не"* && $l6 = *"Не"* ]] ; then
echo -e "Маршрутизация доменов не настроена"
fi
}

inssbwpph(){
sbactive
ins(){
if [ ! -e /etc/s-box/sbwpph ]; then
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
esac
curl -L -o /etc/s-box/sbwpph -# --retry 2 --insecure https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sbwpph_$cpu
chmod +x /etc/s-box/sbwpph
fi
if [[ -n $(ps -e | grep sbwpph) ]]; then
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
fi
v4v6
if [[ -n $v4 ]]; then
sw46=4
else
red "IPv4 отсутствует, убедитесь, что установлен режим WARP-IPv4"
sw46=6
fi
echo
readp "Установите порт для WARP-plus-Socks5 (Enter для 40000 по умолчанию):" port
if [[ -z $port ]]; then
port=40000
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nПорт занят, пожалуйста, введите другой" && readp "Ваш порт:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nПорт занят, пожалуйста, введите другой" && readp "Ваш порт:" port
done
fi
s5port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "socks") | .server_port')
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sed -i "127s/$s5port/$port/g" /etc/s-box/sb10.json
sed -i "165s/$s5port/$port/g" /etc/s-box/sb11.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
}
unins(){
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box/sbwpph.log /etc/s-box/sbwpphid.log
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
}
echo
yellow "1: Сбросить и включить локальный режим Warp для WARP-plus-Socks5"
yellow "2: Сбросить и включить мультирегиональный режим Psiphon для WARP-plus-Socks5"
yellow "3: Остановить режим прокси WARP-plus-Socks5"
yellow "0: Вернуться назад"
readp "Пожалуйста, выберите [0-3]:" menu
if [ "$menu" = "1" ]; then
ins
nohup setsid /etc/s-box/sbwpph -b 127.0.0.1:$port --gool -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbwpphid.log
green "Получение IP... пожалуйста, подождите..." && sleep 20
resv1=$(curl -sm3 --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sm3 -x socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "Не удалось получить IP для WARP-plus-Socks5" && unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --gool -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > /etc/s-box/sbwpph.log
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid $(cat /etc/s-box/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/s-box/sbwpphid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
green "IP для WARP-plus-Socks5 успешно получен, можно настраивать маршрутизацию Socks5"
fi
elif [ "$menu" = "2" ]; then
ins
echo '
Австрия (AT)
Австралия (AU)
Бельгия (BE)
Болгария (BG)
Канада (CA)
Швейцария (CH)
Чехия (CZ)
Германия (DE)
Дания (DK)
Эстония (EE)
Испания (ES)
Финляндия (FI)
Франция (FR)
Великобритания (GB)
Хорватия (HR)
Венгрия (HU)
Ирландия (IE)
Индия (IN)
Италия (IT)
Япония (JP)
Литва (LT)
Латвия (LV)
Нидерланды (NL)
Норвегия (NO)
Польша (PL)
Португалия (PT)
Румыния (RO)
Сербия (RS)
Швеция (SE)
Сингапур (SG)
Словакия (SK)
США (US)
'
readp "Выберите страну (введите две заглавные буквы в конце, например, US для США):" guojia
nohup setsid /etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbwpphid.log
green "Получение IP... пожалуйста, подождите..." && sleep 20
resv1=$(curl -sm3 --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sm3 -x socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "Ошибка получения IP для WARP-plus-Socks5, попробуйте выбрать другую страну" && unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > /etc/s-box/sbwpph.log
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid $(cat /etc/s-box/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/s-box/sbwpphid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
green "IP для WARP-plus-Socks5 успешно получен, можно настраивать маршрутизацию"
fi
elif [ "$menu" = "3" ]; then
unins && green "Функция прокси WARP-plus-Socks5 остановлена"
else
sb
fi
}

sbsm(){
echo
green "YouTube-канал Yongge: https://youtube.com/@ygkkk?sub_confirmation=1 (новости обхода блокировок)"
echo
blue "Видео-инструкции по скрипту sing-box-yg: https://www.youtube.com/playlist?list=PLMgly2AulGG_Affv6skQXWnVqw7XWiPwJ"
echo
blue "Описание скрипта в блоге: http://ygkkk.blogspot.com/2023/10/sing-box-yg.html"
echo
blue "Страница проекта на GitHub: https://github.com/yonggekkk/sing-box-yg"
echo
blue "Рекомендуем новинку: скрипт ArgoSB (максимально автоматизированная настройка)"
blue "Поддержка: AnyTLS, Any-reality, Vless-xhttp-reality, Vless-reality-vision, Shadowsocks-2022, Hysteria2, Tuic, Vmess-ws, Argo туннели"
blue "Страница проекта ArgoSB: https://github.com/yonggekkk/ArgoSB"
echo
}

clear
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo -e "${bblue} ░██     ░██      ░██ ██ ██         ░█${plain}█   ░██     ░██   ░██     ░█${red}█   ░██${plain}  "
echo -e "${bblue}  ░██   ░██      ░██    ░░██${plain}        ░██  ░██      ░██  ░██${red}      ░██  ░██${plain}   "
echo -e "${bblue}   ░██ ░██      ░██ ${plain}                ░██ ██        ░██ █${red}█        ░██ ██  ${plain}   "
echo -e "${bblue}     ░██        ░${plain}██    ░██ ██       ░██ ██        ░█${red}█ ██        ░██ ██  ${plain}  "
echo -e "${bblue}     ░██ ${plain}        ░██    ░░██        ░██ ░██       ░${red}██ ░██       ░██ ░██ ${plain}  "
echo -e "${bblue}     ░█${plain}█          ░██ ██ ██         ░██  ░░${red}██     ░██  ░░██     ░██  ░░██ ${plain}  "
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "GitHub проект Yongge  : github.com/yonggekkk"
white "Блог Yongge           : ygkkk.blogspot.com"
white "YouTube канал Yongge  : www.youtube.com/@ygkkk"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "Скрипт 5-в-1: Vless-reality-vision, Vmess-ws(tls)+Argo, Hy2, Tuic, Anytls"
white "Ярлык скрипта: sb"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. Установить Sing-box (в один клик)" 
green " 2. Удалить/Деинсталлировать Sing-box"
white "----------------------------------------------------------------------------------"
green " 3. Настройки [TLS/UUID/Argo/Приоритет IP/TG уведомления/Warp/Подписки/CDN]" 
green " 4. Сменить основной порт / Добавить Port Hopping и мультиплексирование" 
green " 5. Трехканальная маршрутизация доменов"
green " 6. Остановить / Перезапустить Sing-box"   
green " 7. Обновить скрипт Sing-box-yg"
green " 8. Обновить / Сменить / Выбрать версию ядра Sing-box"
white "----------------------------------------------------------------------------------"
green " 9. Просмотр узлов [Mihomo / SFA+SFI+SFW конфиги / Ссылки подписки / TG уведомления]"
green "10. Посмотреть логи работы Sing-box"
green "11. Включить ускорение BBR+FQ"
green "12. Управление Acme (сертификаты домена)"
green "13. Управление Warp (проверка разблокировки Netflix/ChatGPT)"
green "14. Режим WARP-plus-Socks5 [Локальный Warp / Мультирегиональный Psiphon-VPN]"
green "15. Обновить локальный IP / Настроить вывод IPv4/IPv6"
white "----------------------------------------------------------------------------------"
green "16. Инструкция по использованию скрипта Sing-box-yg"
white "----------------------------------------------------------------------------------"
green " 0. Выход"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
insV=$(cat /etc/s-box/v 2>/dev/null)
latestV=$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1)
if [ -f /etc/s-box/v ]; then
if [ "$insV" = "$latestV" ]; then
echo -e "Актуальная версия скрипта Sing-box-yg: ${bblue}${insV}${plain} (Установлено)"
else
echo -e "Текущая версия скрипта Sing-box-yg: ${bblue}${insV}${plain}"
echo -e "Доступна новая версия Sing-box-yg: ${yellow}${latestV}${plain} (выберите 7 для обновления)"
echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version)${plain}"
fi
else
echo -e "Последняя версия скрипта Sing-box-yg: ${bblue}${latestV}${plain}"
yellow "Скрипт Sing-box-yg не установлен! Сначала выберите пункт 1 для установки"
fi

lapre
if [ -f '/etc/s-box/sb.json' ]; then
if [[ $inscore =~ ^[0-9.]+$ ]]; then
if [ "${inscore}" = "${latcore}" ]; then
echo
echo -e "Последнее стабильное ядро Sing-box: ${bblue}${inscore}${plain} (Установлено)"
echo
echo -e "Последнее тестовое ядро Sing-box: ${bblue}${precore}${plain} (Доступно для смены)"
else
echo
echo -e "Установленное стабильное ядро Sing-box: ${bblue}${inscore}${plain}"
echo -e "Доступно новое стабильное ядро: ${yellow}${latcore}${plain} (выберите 8 для обновления)"
echo
echo -e "Последнее тестовое ядро Sing-box: ${bblue}${precore}${plain} (Доступно для смены)"
fi
else
if [ "${inscore}" = "${precore}" ]; then
echo
echo -e "Последнее тестовое ядро Sing-box: ${bblue}${inscore}${plain} (Установлено)"
echo
echo -e "Последнее стабильное ядро Sing-box: ${bblue}${latcore}${plain} (Доступно для смены)"
else
echo
echo -e "Установленное тестовое ядро Sing-box: ${bblue}${inscore}${plain}"
echo -e "Доступно новое тестовое ядро: ${yellow}${precore}${plain} (выберите 8 для обновления)"
echo
echo -e "Последнее стабильное ядро Sing-box: ${bblue}${latcore}${plain} (Доступно для смены)"
fi
fi
else
echo
echo -e "Последнее стабильное ядро Sing-box: ${bblue}${latcore}${plain}"
echo -e "Последнее тестовое ядро Sing-box: ${bblue}${precore}${plain}"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "Статус VPS:"
echo -e "Система:$blue$op$plain  \c";echo -e "Ядро:$blue$version$plain  \c";echo -e "Процессор:$blue$cpu$plain  \c";echo -e "Виртуализация:$blue$vi$plain  \c";echo -e "BBR:$blue$bbr$plain"
v4v6
if [[ "$v6" == "2a09"* ]]; then
w6="【WARP】"
fi
if [[ "$v4" == "104.28"* ]]; then
w4="【WARP】"
fi
[[ -z $v4 ]] && showv4='IPv4 адрес потерян, переключитесь на IPv6 или переустановите Sing-box' || showv4=$v4$w4
[[ -z $v6 ]] && showv6='IPv6 адрес потерян, переключитесь на IPv4 или переустановите Sing-box' || showv6=$v6$w6
if [[ -z $v4 ]]; then
vps_ipv4='Нет IPv4'      
vps_ipv6="$v6"
location="$v6dq"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="$v4"    
vps_ipv6="$v6"
location="$v4dq"
else
vps_ipv4="$v4"    
vps_ipv6='Нет IPv6'
location="$v4dq"
fi
echo -e "Локальный IPv4: $blue$vps_ipv4$w4$plain    Локальный IPv6: $blue$vps_ipv6$w6$plain"
echo -e "Регион сервера: $blue$location$plain"
if [[ "$sbnh" == "1.10" ]]; then
rpip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[0].domain_strategy') 2>/dev/null
if [[ $rpip = 'prefer_ipv6' ]]; then
v4_6="Приоритет IPv6 на выход ($showv6)"
elif [[ $rpip = 'prefer_ipv4' ]]; then
v4_6="Приоритет IPv4 на выход ($showv4)"
elif [[ $rpip = 'ipv4_only' ]]; then
v4_6="Только IPv4 на выход ($showv4)"
elif [[ $rpip = 'ipv6_only' ]]; then
v4_6="Только IPv6 на выход ($showv6)"
fi
echo -e "Приоритет IP прокси: $blue$v4_6$plain"
fi
if [[ x"${release}" == x"alpine" ]]; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl status sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Статус Sing-box: $blueЗапущено$plain"
elif [[ -z $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Статус Sing-box: $yellowНе запущен, выберите 10 для просмотра логов. Рекомендуется сменить ядро на стабильное или переустановить скрипт$plain"
else
echo -e "Статус Sing-box: $redНе установлен$plain"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
if [ -f '/etc/s-box/sb.json' ]; then
showprotocol
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
readp "Введите номер [0-16]:" Input
case "$Input" in  
 1 ) instsllsingbox;;
 2 ) unins;;
 3 ) changeserv;;
 4 ) changeport;;
 5 ) changefl;;
 6 ) stclre;;
 7 ) upsbyg;; 
 8 ) upsbcroe;;
 9 ) clash_sb_share;;
10 ) sblog;;
11 ) bbr;;
12 ) acme;;
13 ) cfwarp;;
14 ) inssbwpph;;
15 ) wgcfgo && sbshare;;
16 ) sbsm;;
 * ) exit 
esac
