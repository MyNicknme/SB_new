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
red "Скрипт не поддерживает текущую систему. Используйте Ubuntu, Debian или Centos." && exit
fi
export sbfiles="/etc/s-box/sb10.json /etc/s-box/sb11.json /etc/s-box/sb.json"
export sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
#if [[ $(echo "$op" | grep -i -E "arch|alpine") ]]; then
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
red "Скрипт не поддерживает текущую систему $op. Используйте Ubuntu, Debian или Centos." && exit
fi
version=$(uname -r | cut -d "-" -f1)
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
case $(uname -m) in
armv7l) cpu=armv7;;
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "Сейчас скрипт не поддерживает архитектуру $(uname -m)" && exit;;
esac
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
bbr=`sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}'`
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
bbr="Openvz版bbr-plus"
else
bbr="Openvz/Lxc"
fi
hostname=$(hostname)

if [ ! -f sbyg_update ]; then
green "При первой установке выполняется установка необходимых зависимостей для скрипта Sing-box-yg…"
if command -v apk >/dev/null 2>&1; then
apk update
apk add bash libc6-compat jq openssl procps busybox-extras iproute2 iputils coreutils expect git socat iptables grep tar tzdata util-linux
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
apt install jq cron socat busybox iptables-persistent coreutils util-linux -y
elif [ -x "$(command -v yum)" ]; then
yum update -y && yum install epel-release -y
yum install jq socat busybox coreutils util-linux -y
elif [ -x "$(command -v dnf)" ]; then
dnf update -y
dnf install jq socat busybox coreutils util-linux -y
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
red "Обнаружено, что TUN не включён. Сейчас будет предпринята попытка добавить поддержку TUN" && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
green "Не удалось добавить поддержку TUN. Рекомендуется обратиться к провайдеру VPS или включить её в панели управления" && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "Функция автоподдержания TUN запущена"
fi
fi
fi
v4v6(){
v4=$(curl -s4m5 icanhazip.com -k)
v6=$(curl -s6m5 icanhazip.com -k)
v4dq=$(curl -s4m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null)
v6dq=$(curl -s6m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null)
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
yellow "Обнаружен VPS только с IPV6, добавляется NAT64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf
ipv=prefer_ipv6
else
ipv=prefer_ipv4
fi
if [ -n "$(curl -s6m5 icanhazip.com -k)" ]; then
endip="2606:4700:d0::a29f:c001"
else
endip="162.159.192.1"
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
green "Открытие портов и отключение фаервола выполнено"
}

openyn(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "Открыть порты и отключить фаервол?\n1、Да, выполнить (Enter по умолчанию)\n2、Нет, пропустить! Сделаю сам\nВыберите【1-2】：" action
if [[ -z $action ]] || [[ "$action" = "1" ]]; then
close
elif [[ "$action" = "2" ]]; then
echo
else
red "Ошибка ввода, выберите заново" && openyn
fi
}

inssb(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "Какую версию ядра использовать?"
yellow "1：Использовать текущую последнюю стабильную версию ядра (Enter по умолчанию)"
yellow "2：Использовать предыдущую стабильную версию ядра 1.10.7"
readp "Выберите【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
sbcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases/latest | grep -oP 'tag/v\K[0-9.]+' | head -n 1)
else
sbcore='1.10.7'
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
blue "Успешно установлена версия ядра Sing-box：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
else
red "Ядро Sing-box загружено не полностью, установка не удалась. Запустите установку ещё раз" && exit
fi
else
red "Не удалось загрузить ядро Sing-box. Запустите установку ещё раз и проверьте, может ли сеть VPS получить доступ к Github" && exit
fi
}

inscertificate(){
ymzs(){
ym_vl_re=apple.com
echo
blue "SNI-домен для Vless-reality по умолчанию: apple.com"
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
blue "SNI-домен для Vless-reality по умолчанию: apple.com"
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
green "2. Генерация и настройка связанных сертификатов"
echo
blue "Автоматически создаётся самоподписанный сертификат bing……" && sleep 2
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
yellow "Обнаружено, что ранее через скрипт Acme-yg уже был выпущен доменный сертификат Acme：$(cat /root/ygkkkca/ca.log) "
green "Использовать доменный сертификат $(cat /root/ygkkkca/ca.log) ?"
yellow "1：Нет! Использовать самоподписанный сертификат (Enter по умолчанию)"
yellow "2：Да! Использовать доменный сертификат $(cat /root/ygkkkca/ca.log)"
readp "Выберите【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
ymzs
fi
else
green "Если у вас есть уже настроенный домен, хотите выпустить сертификат Acme для домена?"
yellow "1：Нет! Продолжить использовать самоподписанный сертификат (Enter по умолчанию)"
yellow "2：Да! Использовать скрипт Acme-yg для получения сертификата Acme (поддерживаются обычный режим порта 80 и режим Dns API)"
readp "Выберите【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
red "Не удалось выпустить сертификат Acme, продолжаем использовать самоподписанный сертификат" 
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
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nПорт занят, введите порт заново" && readp "Пользовательский порт:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nПорт занят, введите порт заново" && readp "Пользовательский порт:" port
done
fi
blue "Подтверждённый порт：$port" && sleep 2
}

vlport(){
readp "\nЗадайте порт Vless-reality (Enter — случайный порт в диапазоне 10000-65535)：" port
chooseport
port_vl_re=$port
}
vmport(){
readp "\nЗадайте порт Vmess-ws (Enter — случайный порт в диапазоне 10000-65535)：" port
chooseport
port_vm_ws=$port
}
hy2port(){
readp "\nЗадайте основной порт Hysteria2 (Enter — случайный порт в диапазоне 10000-65535)：" port
chooseport
port_hy2=$port
}
tu5port(){
readp "\nЗадайте основной порт Tuic5 (Enter — случайный порт в диапазоне 10000-65535)：" port
chooseport
port_tu=$port
}
anport(){
readp "\nЗадайте основной порт Anytls, доступно на новых версиях ядра (Enter — случайный порт в диапазоне 10000-65535)：" port
chooseport
port_an=$port
}

insport(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "3. Настройка портов для каждого протокола"
yellow "1：Автоматически сгенерировать случайный порт для каждого протокола (в диапазоне 10000-65535), Enter по умолчанию. Убедитесь, что в панели VPS открыты все порты"
yellow "2：Задать порты для каждого протокола вручную. Убедитесь, что в панели VPS открыты указанные порты"
readp "Введите【1-2】：" port
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
blue "В зависимости от того, включён ли TLS для протокола Vmess-ws, случайно выбран стандартный порт с поддержкой CDN preferred IP：$port_vm_ws"
else
vlport && vmport && hy2port && tu5port
if [[ "$sbnh" != "1.10" ]]; then
anport
fi
fi
echo
blue "Подтверждены следующие порты протоколов"
blue "Порт Vless-reality：$port_vl_re"
blue "Порт Vmess-ws：$port_vm_ws"
blue "Порт Hysteria-2：$port_hy2"
blue "Порт Tuic-v5：$port_tu"
if [[ "$sbnh" != "1.10" ]]; then
blue "Порт Anytls：$port_an"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "4. Автоматическая генерация единого uuid (пароля) для всех протоколов"
uuid=$(/etc/s-box/sing-box generate uuid)
blue "Подтверждён uuid (пароль)：${uuid}"
blue "Подтверждён путь path для Vmess：${uuid}-vm"
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
if command -v apk >/dev/null 2>&1; then
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
if command -v apk >/dev/null 2>&1; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl is-active sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
v4v6
if [[ -n $v4 && -n $v6 ]]; then
green "Настройка вывода конфигурации IPv4/IPV6"
yellow "1：Обновить локальный IP и использовать вывод конфигурации IPV4 (Enter по умолчанию) "
yellow "2：Обновить локальный IP и использовать вывод конфигурации IPV6"
readp "Выберите【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ]; then
server_ip="$v4"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v4"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
server_ip="[$v6]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v6"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
else
yellow "VPS не является двухстековым, переключение вывода IP-конфигурации не поддерживается"
serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
if [[ "$serip" =~ : ]]; then
server_ip="[$serip]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
server_ip="$serip"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
fi
else
red "Сервис Sing-box не запущен" && exit
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
red "🚀【 vless-reality-vision 】Информация об узле如下：" && sleep 2
echo
echo "Ссылка для импорта【v2ran(переключить ядро на singbox)、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vl_link${plain}"
echo
echo "QR-код【v2ran(переключить ядро на singbox)、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vl_reality.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resvmess(){
if [[ "$tls" = "false" ]]; then
if ps -ef 2>/dev/null | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" >/dev/null 2>&1; then
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】Временная информация об узле如下(можно выбрать 3-8-3, пользовательский CDN-адрес优选)：" && sleep 2
echo
echo "Ссылка для импорта【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "QR-код【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argols.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argols.txt)"
fi
if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
argogd=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】Информация о постоянном узле如下 (можно выбрать 3-8-3, пользовательский CDN-адрес优选)：" && sleep 2
echo
echo "Ссылка для импорта【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "QR-код【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argogd.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argogd.txt)"
fi
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws 】Информация об узле如下 (рекомендуется выбрать 3-8-1 и настроить как CDN-узел с приоритетным IP)：" && sleep 2
echo
echo "Ссылка для импорта【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "QR-код【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws.txt)"
else
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws-tls 】Информация об узле如下 (рекомендуется выбрать 3-8-1 и настроить как CDN-узел с приоритетным IP)：" && sleep 2
echo
echo "Ссылка для импорта【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "QR-код【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
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
red "🚀【 Hysteria-2 】Информация об узле如下：" && sleep 2
echo
echo "Ссылка для импорта【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$hy2_link${plain}"
echo
echo "QR-код【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/hy2.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

restu5(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
tuic5_link="tuic://$uuid:$uuid@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&allow_insecure=$ins&allowInsecure=$ins#tu5-$hostname"
echo "$tuic5_link" > /etc/s-box/tuic5.txt
red "🚀【 Tuic-v5 】Информация об узле如下：" && sleep 2
echo
echo "Ссылка для импорта【v2rayn、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$tuic5_link${plain}"
echo
echo "QR-код【v2rayn、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/tuic5.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resan(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
an_link="anytls://$uuid@$sb_an_ip:$an_port?&sni=$an_name&allowInsecure=$ins_an#anytls-$hostname"
echo "$an_link" > /etc/s-box/an.txt
red "🚀【 Anytls】Информация об узле如下：" && sleep 2
echo
echo "Ссылка для импорта【v2rayn、小火箭shadowrocket】"
echo -e "${yellow}$an_link${plain}"
echo
echo "QR-код【v2rayn、nekobox、小火箭shadowrocket】"
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
        "strategy": "prefer_ipv4",
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
                "server_name": "$tu5_name",
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
if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run' && ps -ef 2>/dev/null | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" >/dev/null 2>&1 && [ "$tls" = "false" ]; then
cat > /etc/s-box/sbox.json <<EOF
$(sball)
$(sbany2)
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo固定-$hostname",
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
            "tag": "vmess-argo固定-$hostname",
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
            "tag": "vmess-tls-argo临时-$hostname",
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
            "tag": "vmess-argo临时-$hostname",
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
        "vmess-tls-argo固定-$hostname",
        "vmess-argo固定-$hostname",
        "vmess-tls-argo临时-$hostname",
        "vmess-argo临时-$hostname"
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
        "vmess-tls-argo固定-$hostname",
        "vmess-argo固定-$hostname",
        "vmess-tls-argo临时-$hostname",
        "vmess-argo临时-$hostname"
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

cat > /etc/s-box/clmi.yaml <<EOF
$(clall)

$(clany2)

- name: vmess-tls-argo固定-$hostname                         
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


- name: vmess-argo固定-$hostname                         
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
    path: "$ws_path"                             
    headers:
      Host: $argogd

- name: vmess-tls-argo临时-$hostname                         
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

- name: vmess-argo临时-$hostname                         
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
- name: Балансировка нагрузки
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
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname

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
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname
    
- name: 🌍Выбор прокси-узла
  type: select
  proxies:
    - Балансировка нагрузки                                         
    - Автовыбор
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍Выбор прокси-узла
EOF

elif ! ps -ef 2>/dev/null | grep -q '[c]loudflared.*run' && ps -ef 2>/dev/null | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" >/dev/null 2>&1 && [ "$tls" = "false" ]; then
cat > /etc/s-box/sbox.json <<EOF
$(sball)
$(sbany2)
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo临时-$hostname",
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
            "tag": "vmess-argo临时-$hostname",
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
        "vmess-tls-argo临时-$hostname",
        "vmess-argo临时-$hostname"
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
        "vmess-tls-argo临时-$hostname",
        "vmess-argo临时-$hostname"
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

cat > /etc/s-box/clmi.yaml <<EOF
$(clall)








$(clany2)

- name: vmess-tls-argo临时-$hostname                         
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

- name: vmess-argo临时-$hostname                         
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
- name: Балансировка нагрузки
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
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname

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
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname
    
- name: 🌍Выбор прокси-узла
  type: select
  proxies:
    - Балансировка нагрузки                                         
    - Автовыбор
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍Выбор прокси-узла
EOF

elif ps -ef 2>/dev/null | grep -q '[c]loudflared.*run' && ! ps -ef 2>/dev/null | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" >/dev/null 2>&1 && [ "$tls" = "false" ]; then
cat > /etc/s-box/sbox.json <<EOF
$(sball)
$(sbany2)
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo固定-$hostname",
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
            "tag": "vmess-argo固定-$hostname",
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
        "vmess-tls-argo固定-$hostname",
        "vmess-argo固定-$hostname"
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
        "vmess-tls-argo固定-$hostname",
        "vmess-argo固定-$hostname"
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

cat > /etc/s-box/clmi.yaml <<EOF
$(clall)






$(clany2)

- name: vmess-tls-argo固定-$hostname                         
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

- name: vmess-argo固定-$hostname                         
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
    path: "$ws_path"                             
    headers:
      Host: $argogd

proxy-groups:
- name: Балансировка нагрузки
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
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname

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
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    
- name: 🌍Выбор прокси-узла
  type: select
  proxies:
    - Балансировка нагрузки                                         
    - Автовыбор
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    $(clany1)
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍Выбор прокси-узла
EOF

else
cat > /etc/s-box/sbox.json <<EOF
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

cat > /etc/s-box/clmi.yaml <<EOF
$(clall)

$(clany2)

proxy-groups:
- name: Балансировка нагрузки
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
    
- name: 🌍Выбор прокси-узла
  type: select
  proxies:
    - Балансировка нагрузки                                         
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
  - MATCH,🌍Выбор прокси-узла
EOF
fi
}

cfargo_ym(){
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
echo
yellow "1：Добавить или удалить временный туннель Argo"
yellow "2：Добавить или удалить фиксированный туннель Argo"
yellow "0：Вернуться назад"
readp "Выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
cfargo
elif [ "$menu" = "2" ]; then
cfargoym
else
changeserv
fi
else
yellow "Так как у vmess включён tls, функция туннеля Argo недоступна" && sleep 2
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
green "Текущий домен фиксированного туннеля Argo：$(cat /etc/s-box/sbargoym.log 2>/dev/null)"
green "Текущий Token фиксированного туннеля Argo：$(cat /etc/s-box/sbargotoken.log 2>/dev/null)"
fi
echo
green "Перейдите на официальный сайт Cloudflare --- Zero Trust --- Сеть --- Коннекторы и создайте фиксированный туннель"
yellow "1：Сбросить/задать домен фиксированного туннеля Argo"
yellow "2：Остановить фиксированный туннель Argo"
yellow "0：Вернуться назад"
readp "Выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
cloudflaredargo
readp "Введите Token фиксированного туннеля Argo: " argotoken
readp "Введите домен фиксированного туннеля Argo: " argoym
pid=$(ps -ef 2>/dev/null | awk '/[c]loudflared.*run/ {print $2}')
[ -n "$pid" ] && kill -9 "$pid" >/dev/null 2>&1
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
ExecStart=/etc/s-box/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${argotoken}"
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
fi
fi
echo ${argoym} > /etc/s-box/sbargoym.log
echo ${argotoken} > /etc/s-box/sbargotoken.log
argo=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
sbshare > /dev/null 2>&1
blue "Настройка фиксированного туннеля Argo завершена, фиксированный домен：$argo"
elif [ "$menu" = "2" ]; then
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
sbshare > /dev/null 2>&1
green "Фиксированный туннель Argo остановлен"
else
cfargo_ym
fi
}

cfargo(){
echo
yellow "1：Сбросить домен временного туннеля Argo"
yellow "2：Остановить временный туннель Argo"
yellow "0：Вернуться назад"
readp "Выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
green "Пожалуйста, подождите……"
cloudflaredargo
ps -ef | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" | awk '{print $2}' | xargs kill 2>/dev/null
nohup /etc/s-box/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
sleep 20
if [[ -n $(curl -sL https://$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')/ -I | awk 'NR==1 && /404|400|503/') ]]; then
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
sbshare > /dev/null 2>&1
blue "Временный туннель Argo успешно создан, проверка домена действительна：$argo" && sleep 2
if command -v apk >/dev/null 2>&1; then
cat > /etc/local.d/alpineargo.start <<'EOF'
#!/bin/bash
sleep 10
nohup /etc/s-box/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
sleep 10
printf "9\n1\n" | bash /usr/bin/sb > /dev/null 2>&1
EOF
chmod +x /etc/local.d/alpineargo.start
rc-update add local default >/dev/null 2>&1
else
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/url http/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup /etc/s-box/cloudflared tunnel --url http://localhost:$(sed '\''s://.*::g'\'' /etc/s-box/sb.json | jq -r '\''.inbounds[1].listen_port'\'') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 & sleep 10 && printf \"9\n1\n\" | bash /usr/bin/sb > /dev/null 2>&1"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
fi
else
yellow "Проверка временного домена Argo сейчас недоступна, попробуйте позже"
fi
elif [ "$menu" = "2" ]; then
ps -ef | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" | awk '{print $2}' | xargs kill 2>/dev/null
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/url http/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
rm -rf /etc/s-box/vm_ws_argols.txt
rm -rf /etc/local.d/alpineargo.start
sbshare > /dev/null 2>&1
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
blue "Ключи и ID для Vless-reality будут сгенерированы автоматически……"
key_pair=$(/etc/s-box/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" > /etc/s-box/public.key
short_id=$(/etc/s-box/sing-box generate rand --hex 4)
wget -q -O /root/geoip.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
wget -q -O /root/geosite.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "5、Автоматическое создание исходящего аккаунта warp-wireguard" && sleep 2
warpwg
inssbjsonser
sbservice
sbactive
#curl -sL https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
lnsb && blue "Скрипт Sing-box-yg успешно установлен, быстрый запуск скрипта: sb" && cronsb
echo
wgcfgo
sbshare
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
blue "Можно выбрать пункт 9, чтобы обновить и показать конфигурации всех протоколов и ссылки для分享"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

changeym(){
[ -f /root/ygkkkca/ca.log ] && ymzs="$yellowПереключиться на доменный сертификат：$(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellowДоменный сертификат не получен, переключение невозможно$plain"
vl_na="Используемый сейчас домен：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')。$yellowМожно заменить на домен, соответствующий требованиям reality, домен сертификата не поддерживается$plain"
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
[[ "$tls" = "false" ]] && vm_na="Сейчас TLS отключён。$ymzs ${yellow}если включить TLS, туннель Argo нельзя будет использовать${plain}" || vm_na="Сейчас используется доменный сертификат：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellowесли переключить на отключённый TLS, туннель Argo станет доступен$plain"
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_na="Сейчас используется самоподписанный сертификат bing。$ymzs" || hy2_na="Сейчас используется доменный сертификат：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellowпереключить на самоподписанный сертификат bing$plain"
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_na="Сейчас используется самоподписанный сертификат bing。$ymzs" || tu5_na="Сейчас используется доменный сертификат：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellowпереключить на самоподписанный сертификат bing$plain"
an_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
[[ "$an_sniname" = '/etc/s-box/private.key' ]] && an_na="Сейчас используется самоподписанный сертификат bing。$ymzs" || an_na="Сейчас используется доменный сертификат：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellowпереключить на самоподписанный сертификат bing$plain"
echo
green "Выберите протокол, для которого нужно переключить режим сертификата"
green "1：протокол vless-reality，$vl_na"
if [[ -f /root/ygkkkca/ca.log ]]; then
green "2：протокол vmess-ws，$vm_na"
green "3：протокол Hysteria2，$hy2_na"
green "4：протокол Tuic5，$tu5_na"
if [[ "$sbnh" != "1.10" ]]; then
green "5：протокол Anytls，$an_na"
fi
else
red "Поддерживается только пункт 1 (vless-reality)。Так как доменный сертификат не получен, пункты переключения сертификатов для vmess-ws、Hysteria-2、Tuic-v5、Anytls временно не отображаются"
fi
green "0：Вернуться назад"
readp "Выберите：" menu
if [ "$menu" = "1" ]; then
readp "Введите домен vless-reality (Enter = apple.com)：" menu
ym_vl_re=${menu:-apple.com}
a=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')
b=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.reality.handshake.server')
c=$(cat /etc/s-box/vl_reality.txt | cut -d'=' -f5 | cut -d'&' -f1)
echo $sbfiles | xargs -n1 sed -i "23s/$a/$ym_vl_re/"
echo $sbfiles | xargs -n1 sed -i "27s/$b/$ym_vl_re/"
restartsb && sbshare > /dev/null 2>&1
blue "Замена доменного сертификата Vless-reality завершена"
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
restartsb && sbshare > /dev/null 2>&1
blue "Замена доменного сертификата протокола vmess-ws завершена"
echo
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
blue "Текущий порт Vmess-ws(tls)：$vm_port"
[[ "$tls" = "false" ]] && blue "Помните: можно зайти в главное меню, пункт 4-2, и изменить порт Vmess-ws на любой из 7 портов группы 80 (80、8080、8880、2052、2082、2086、2095), чтобы использовать оптимальный CDN IP" || blue "Помните: можно зайти в главное меню, пункт 4-2, и изменить порт Vmess-ws-tls на любой из 6 портов группы 443 (443、8443、2053、2083、2087、2096), чтобы использовать оптимальный CDN IP"
echo
else
red "Доменный сертификат пока не получен, переключение невозможно。В главном меню выберите пункт 12 и выполните получение сертификата Acme" && sleep 2 && sb
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
restartsb && sbshare > /dev/null 2>&1
blue "Замена доменного сертификата протокола Hysteria2 завершена"
else
red "Доменный сертификат пока не получен, переключение невозможно。В главном меню выберите пункт 12 и выполните получение сертификата Acme" && sleep 2 && sb
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
restartsb && sbshare > /dev/null 2>&1
blue "Замена доменного сертификата протокола Tuic5 завершена"
else
red "Доменный сертификат пока не получен, переключение невозможно。В главном меню выберите пункт 12 и выполните получение сертификата Acme" && sleep 2 && sb
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
restartsb && sbshare > /dev/null 2>&1
blue "Замена доменного сертификата протокола Anytls завершена"
else
red "Доменный сертификат пока не получен, переключение невозможно。В главном меню выберите пункт 12 и выполните получение сертификата Acme" && sleep 2 && sb
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
[[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="не добавлено"
[[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="не добавлено"
}

changeport(){
sbactive
allports
fports(){
readp "\nВведите диапазон перенаправляемых портов (в пределах 1000-65535, формат: меньший:больший)：" rangeport
if [[ $rangeport =~ ^([1-9][0-9]{3,4}:[1-9][0-9]{3,4})$ ]]; then
b=${rangeport%%:*}
c=${rangeport##*:}
if [[ $b -ge 1000 && $b -le 65535 && $c -ge 1000 && $c -le 65535 && $b -lt $c ]]; then
iptables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "Подтверждён диапазон перенаправляемых портов：$rangeport"
else
red "Введённый диапазон портов находится вне допустимого диапазона" && fports
fi
else
red "Неверный формат ввода。Формат: меньший:больший" && fports
fi
echo
}
fport(){
readp "\nВведите один перенаправляемый порт (в пределах 1000-65535)：" onlyport
if [[ $onlyport -ge 1000 && $onlyport -le 65535 ]]; then
iptables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "Подтверждён перенаправляемый порт：$onlyport"
else
blue "Введённый порт находится вне допустимого диапазона" && fport
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
green "Для Vless-reality、Vmess-ws、Anytls можно изменить только один порт; для vmess-ws учитывайте сброс порта Argo"
green "Hysteria2 и Tuic5 поддерживают смену основного порта, а также добавление и удаление нескольких перенаправляемых портов"
green "Hysteria2 поддерживает прыгающие порты, и вместе с Tuic5 оба поддерживают повторное использование нескольких портов"
echo
green "1：протокол Vless-reality ${yellow}порт:$vl_port${plain}"
green "2：протокол Vmess-ws ${yellow}порт:$vm_port${plain}"
green "3：протокол Hysteria2 ${yellow}порт:$hy2_port  несколько перенаправляемых портов: $hy2zfport${plain}"
green "4：протокол Tuic5 ${yellow}порт:$tu5_port  несколько перенаправляемых портов: $tu5zfport${plain}"
if [[ "$sbnh" != "1.10" ]]; then
green "5：протокол Anytls ${yellow}порт:$an_port${plain}"
fi
green "0：Вернуться назад"
readp "Выберите протокол, для которого нужно изменить порт：" menu
if [ "$menu" = "1" ]; then
vlport
echo $sbfiles | xargs -n1 sed -i "14s/$vl_port/$port_vl_re/"
restartsb && sbshare > /dev/null 2>&1
blue "Смена порта Vless-reality завершена"
echo
elif [ "$menu" = "5" ]; then
anport
echo $sbfiles | xargs -n1 sed -i "110s/$an_port/$port_an/"
restartsb && sbshare > /dev/null 2>&1
blue "Смена порта Anytls завершена"
echo
elif [ "$menu" = "2" ]; then
vmport
echo $sbfiles | xargs -n1 sed -i "41s/$vm_port/$port_vm_ws/"
restartsb && sbshare > /dev/null 2>&1
blue "Смена порта Vmess-ws завершена"
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
blue "Помните: если Argo используется, временный туннель нужно обязательно сбросить, а порт в интерфейсе настроек CF для фиксированного туннеля нужно изменить на $port_vm_ws"
else
blue "Так как TLS уже включён, туннель Argo сейчас недоступен"
fi
echo
elif [ "$menu" = "3" ]; then
green "1：Сменить основной порт Hysteria2 (старые дополнительные порты будут автоматически сброшены и удалены)"
green "2：Добавить несколько портов для Hysteria2"
green "3：Сбросить и удалить несколько портов Hysteria2"
green "0：Вернуться назад"
readp "Выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
if [ -n $hy2_ports ]; then
hy2deports
hy2port
echo $sbfiles | xargs -n1 sed -i "67s/$hy2_port/$port_hy2/"
restartsb && sbshare > /dev/null 2>&1
else
hy2port
echo $sbfiles | xargs -n1 sed -i "67s/$hy2_port/$port_hy2/"
restartsb && sbshare > /dev/null 2>&1
fi
blue "Смена порта Hysteria2 завершена"
elif [ "$menu" = "2" ]; then
green "1：Добавить диапазон портов Hysteria2"
green "2：Добавить один порт Hysteria2"
green "0：Вернуться назад"
readp "Выберите【0-2】：" menu
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
if [ "$menu" = "1" ]; then
fports && sbshare > /dev/null 2>&1 && changeport
elif [ "$menu" = "2" ]; then
fport && sbshare > /dev/null 2>&1 && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n $hy2_ports ]; then
hy2deports && sbshare > /dev/null 2>&1 && changeport
else
yellow "Для Hysteria2 несколько портов не настроены" && changeport
fi
else
changeport
fi

elif [ "$menu" = "4" ]; then
green "1：Сменить основной порт Tuic5 (старые дополнительные порты будут автоматически сброшены и удалены)"
green "2：Добавить несколько портов Tuic5"
green "3：Сбросить и удалить несколько портов Tuic5"
green "0：Вернуться назад"
readp "Выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
if [ -n $tu5_ports ]; then
tu5deports
tu5port
echo $sbfiles | xargs -n1 sed -i "89s/$tu5_port/$port_tu/"
restartsb && sbshare > /dev/null 2>&1
else
tu5port
echo $sbfiles | xargs -n1 sed -i "89s/$tu5_port/$port_tu/"
restartsb && sbshare > /dev/null 2>&1
fi
blue "Смена порта Tuic5 завершена"
elif [ "$menu" = "2" ]; then
green "1：Добавить диапазон портов Tuic5"
green "2：Добавить один порт Tuic5"
green "0：Вернуться назад"
readp "Выберите【0-2】：" menu
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
if [ "$menu" = "1" ]; then
fports && sbshare > /dev/null 2>&1 && changeport
elif [ "$menu" = "2" ]; then
fport && sbshare > /dev/null 2>&1 && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n $tu5_ports ]; then
tu5deports && sbshare > /dev/null 2>&1 && changeport
else
yellow "Для Tuic5 несколько портов не настроены" && changeport
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
green "UUID (пароль) для всех протоколов：$olduuid"
green "Путь path для Vmess：$oldvmpath"
echo
yellow "1：Задать свой UUID (пароль) для всех протоколов"
yellow "2：Задать свой путь path для Vmess"
yellow "0：Вернуться назад"
readp "Выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
readp "Введите UUID, он должен быть в формате UUID; если не знаете — нажмите Enter (сброс и случайная генерация UUID)：" menu
if [ -z "$menu" ]; then
uuid=$(/etc/s-box/sing-box generate uuid)
else
uuid=$menu
fi
echo $sbfiles | xargs -n1 sed -i "s/$olduuid/$uuid/g"
restartsb && sbshare > /dev/null 2>&1
blue "Подтверждён UUID (пароль)：${uuid}" 
blue "Подтверждён путь path для Vmess：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')"
elif [ "$menu" = "2" ]; then
readp "Введите путь path для Vmess, Enter = без изменений：" menu
if [ -z "$menu" ]; then
echo
else
vmpath=$menu
echo $sbfiles | xargs -n1 sed -i "50s#$oldvmpath#$vmpath#g"
restartsb && sbshare > /dev/null 2>&1
fi
blue "Подтверждён путь path для Vmess：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')"
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
readp "1. Приоритет IPV4\n2. Приоритет IPV6\n3. Только IPV4\n4. Только IPV6\nВыберите：" choose
if [[ $choose == "1" && -n $v4 ]]; then
rrpip="prefer_ipv4" && chip && v4_6="Приоритет IPV4($v4)"
elif [[ $choose == "2" && -n $v6 ]]; then
rrpip="prefer_ipv6" && chip && v4_6="Приоритет IPV6($v6)"
elif [[ $choose == "3" && -n $v4 ]]; then
rrpip="ipv4_only" && chip && v4_6="Только IPV4($v4)"
elif [[ $choose == "4" && -n $v6 ]]; then
rrpip="ipv6_only" && chip && v4_6="Только IPV6($v6)"
else 
red "Сейчас отсутствует выбранный вами IPV4/IPV6 адрес, либо допущена ошибка ввода" && changeip
fi
blue "Текущий изменённый приоритет IP：${v4_6}" && sb
else
red "Доступно только для ядра 1.10.7" && exit
fi
}

tgsbshow(){
echo
yellow "1：Сбросить/задать Token Telegram-бота и ID пользователя"
yellow "0：Вернуться назад"
readp "Выберите【0-1】：" menu
if [ "$menu" = "1" ]; then
rm -rf /etc/s-box/sbtg.sh
readp "Введите Token Telegram-бота: " token
telegram_token=$token
readp "Введите ID пользователя Telegram-бота: " userid
telegram_id=$userid
echo '#!/bin/bash
export LANG=en_US.UTF-8
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
total_lines=$(wc -l < /etc/s-box/clmi.yaml)
half=$((total_lines / 2))
head -n $half /etc/s-box/clmi.yaml > /etc/s-box/clash_meta_client1.txt
tail -n +$((half + 1)) /etc/s-box/clmi.yaml > /etc/s-box/clash_meta_client2.txt

total_lines=$(wc -l < /etc/s-box/sbox.json)
quarter=$((total_lines / 4))
head -n $quarter /etc/s-box/sbox.json > /etc/s-box/sing_box_client1.txt
tail -n +$((quarter + 1)) /etc/s-box/sbox.json | head -n $quarter > /etc/s-box/sing_box_client2.txt
tail -n +$((2 * quarter + 1)) /etc/s-box/sbox.json | head -n $quarter > /etc/s-box/sing_box_client3.txt
tail -n +$((3 * quarter + 1)) /etc/s-box/sbox.json > /etc/s-box/sing_box_client4.txt

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
m11=$(cat /etc/s-box/jhsub.txt 2>/dev/null)
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
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка для分享 Vless-reality-vision 】：поддерживаются v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m1}")
if [[ -f /etc/s-box/vm_ws.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка для分享 Vmess-ws 】：поддерживаются v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m2}")
fi
if [[ -f /etc/s-box/vm_ws_argols.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка для分享 Vmess-ws(tls)+Argo с временным доменом 】：поддерживаются v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3}")
fi
if [[ -f /etc/s-box/vm_ws_argogd.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка для分享 Vmess-ws(tls)+Argo с постоянным доменом 】：поддерживаются v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3_5}")
fi
if [[ -f /etc/s-box/vm_ws_tls.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка для分享 Vmess-ws-tls 】：поддерживаются v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m4}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка для分享 Hysteria-2 】：поддерживаются v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка для分享 Tuic-v5 】：поддерживается nekobox "$'"'"'\n\n'"'"'"${message_text_m6}")
if [[ "$sbnh" != "1.10" ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка для分享 Anytls 】：доступно только на новом ядре "$'"'"'\n\n'"'"'"${message_text_m12}")
fi
if [[ -f /etc/s-box/sing_box_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка подписки Sing-box 】：поддерживаются SFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m9}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Конфигурационный файл Sing-box (4 части) 】：поддерживаются SFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m7}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5_5}")
fi

if [[ -f /etc/s-box/clash_meta_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Ссылка подписки Mihomo 】：поддерживаются клиенты Mihomo "$'"'"'\n\n'"'"'"${message_text_m10}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Конфигурационный файл Mihomo (2 части) 】：поддерживаются клиенты Mihomo "$'"'"'\n\n'"'"'"${message_text_m8}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m8_5}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Агрегированные узлы 】：поддерживается nekobox "$'"'"'\n\n'"'"'"${message_text_m11}")

if [ $? == 124 ];then
echo Запрос к TG_api превысил время ожидания, проверьте, завершилась ли перезагрузка сети и есть ли доступ к TG
fi
resSuccess=$(echo "$res" | jq -r ".ok")
if [[ $resSuccess = "true" ]]; then
echo "Отправка в TG выполнена успешно";
else
echo "Ошибка отправки в TG, проверьте Token и ID Telegram-бота";
fi
' > /etc/s-box/sbtg.sh
sed -i "s/telegram_token/$telegram_token/g" /etc/s-box/sbtg.sh
sed -i "s/telegram_id/$telegram_id/g" /etc/s-box/sbtg.sh
green "Настройка завершена! Убедитесь, что TG-бот уже активирован!"
tgnotice
else
changeserv
fi
}

tgnotice(){
if [[ -f /etc/s-box/sbtg.sh ]]; then
green "Подождите 5 секунд, TG-бот готовится отправить уведомление……"
sbshare > /dev/null 2>&1
bash /etc/s-box/sbtg.sh
else
yellow "Функция уведомлений TG не настроена"
fi
exit
}

changeserv(){
sbactive
echo
green "Доступны следующие варианты изменения конфигурации Sing-box:"
readp "1：Сменить адрес маскировки Reality-домена, переключить самоподписанный сертификат и Acme-доменный сертификат, включить/выключить TLS\n2：Сменить UUID (пароль) для всех протоколов и путь Vmess-Path\n3：Настроить временный туннель Argo или постоянный туннель\n4：Переключить приоритет прокси между IPV4 и IPV6 (доступно только для ядра 1.10.7)\n5：Настроить уведомления узлов через Telegram\n6：Сменить исходящий аккаунт Warp-wireguard\n7：Настроить ссылку подписки через Gitlab\n8：Настроить ссылку подписки по локальному IP\n9：Настроить оптимальный CDN-адрес для всех узлов Vmess\n0：Вернуться назад\nВыберите【0-9】：" menu
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
ipsub
elif [ "$menu" = "9" ];then
vmesscfadd
else 
sb
fi
}

ipsub(){
subtokenipsub(){
echo
readp "Введите пароль пути ссылки подписки (Enter = использовать текущий UUID)：" menu
if [ -z "$menu" ]; then
subtoken="$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')"
else
subtoken="$menu"
fi
rm -rf /root/websbox/"$(cat /etc/s-box/subtoken.log 2>/dev/null)"
echo $subtoken > /etc/s-box/subtoken.log
green "Пароль пути ссылки подписки：$(cat /etc/s-box/subtoken.log 2>/dev/null)"
}
subportipsub(){
echo
readp "Введите свободный и доступный порт для ссылки подписки (Enter = случайный порт)：" menu
if [ -z "$menu" ]; then
subport=$(shuf -i 10000-65535 -n 1)
else
subport="$menu"
fi
echo $subport > /etc/s-box/subport.log
green "Порт ссылки подписки：$(cat /etc/s-box/subport.log 2>/dev/null)"
}
echo
yellow "1：Сбросить/установить ссылку подписки по локальному IP"
yellow "2：Сменить пароль пути ссылки подписки"
yellow "3：Сменить порт ссылки подписки"
yellow "4：Удалить ссылку подписки по локальному IP"
yellow "0：Вернуться назад"
readp "Выберите【0-4】：" menu
if [ "$menu" = "1" ]; then
subtokenipsub && subportipsub
elif [ "$menu" = "2" ];then
subtokenipsub
elif [ "$menu" = "3" ];then
subportipsub
elif [ "$menu" = "4" ];then
kill -15 $(pgrep -f 'websbox' 2>/dev/null) >/dev/null 2>&1
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/websbox/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
rm -rf /root/websbox
rm -rf /etc/local.d/alpinesub.start
green "Ссылка подписки по локальному IP успешно удалена" && sleep 3 && exit
else
changeserv
fi
echo
green "Пожалуйста, подождите…………"
kill -15 $(pgrep -f 'websbox' 2>/dev/null) >/dev/null 2>&1
mkdir -p /root/websbox/"$(cat /etc/s-box/subtoken.log 2>/dev/null)"
ln -sf /etc/s-box/clmi.yaml /root/websbox/"$(cat /etc/s-box/subtoken.log 2>/dev/null)"/clmi.yaml
ln -sf /etc/s-box/sbox.json /root/websbox/"$(cat /etc/s-box/subtoken.log 2>/dev/null)"/sbox.json
ln -sf /etc/s-box/jhsub.txt /root/websbox/"$(cat /etc/s-box/subtoken.log 2>/dev/null)"/jhsub.txt
if command -v apk >/dev/null 2>&1; then
busybox-extras httpd -f -p "$(cat /etc/s-box/subport.log 2>/dev/null)" -h /root/websbox > /dev/null 2>&1 &
else
busybox httpd -f -p "$(cat /etc/s-box/subport.log 2>/dev/null)" -h /root/websbox > /dev/null 2>&1 &
fi
sleep 5
if command -v apk >/dev/null 2>&1; then
cat > /etc/local.d/alpinesub.start <<'EOF'
#!/bin/bash
sleep 10
busybox-extras httpd -f -p $(cat /etc/s-box/subport.log 2>/dev/null) -h /root/websbox > /dev/null 2>&1 &
EOF
chmod +x /etc/local.d/alpinesub.start
rc-update add local default >/dev/null 2>&1
else
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/websbox/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "busybox httpd -f -p $(cat /etc/s-box/subport.log 2>/dev/null) -h /root/websbox > /dev/null 2>&1 &"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
fi
sbshare > /dev/null 2>&1
sleep 1 && green "Ссылка подписки по локальному IP успешно обновлена" && sleep 3 && sb
}

vmesscfadd(){
echo
green "Рекомендуется использовать официальные CDN-домены крупных мировых компаний или организаций в качестве оптимального CDN-адреса:"
blue "www.visa.com.sg"
blue "www.wto.org"
blue "www.web.com"
blue "yg1.ygkkk.dpdns.org (цифру 1 в yg1 можно заменить на любую от 1 до 11, поддерживается Yongge)"
echo
yellow "1：Задать свой оптимальный CDN-адрес для основного узла Vmess-ws(tls)"
yellow "2：Для пункта 1 — сбросить клиентский домен host/sni (домен, чей IP указывает на Cloudflare)"
yellow "3：Задать свой оптимальный CDN-адрес для узла Vmess-ws(tls)-Argo"
yellow "0：Вернуться назад"
readp "Выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
echo
green "Убедитесь, что IP вашего VPS уже привязан к домену в Cloudflare"
if [[ ! -f /etc/s-box/cfymjx.txt ]] 2>/dev/null; then
readp "Введите клиентский домен host/sni (домен, чей IP указывает на Cloudflare)：" menu
echo "$menu" > /etc/s-box/cfymjx.txt
fi
echo
readp "Введите свой оптимальный IP/домен：" menu
echo "$menu" > /etc/s-box/cfvmadd_local.txt
green "Настройка выполнена успешно, выберите в главном меню пункт 9 для обновления конфигурации узлов" && sleep 2 && vmesscfadd
elif  [ "$menu" = "2" ]; then
rm -rf /etc/s-box/cfymjx.txt
green "Сброс выполнен успешно, можно выбрать пункт 1 и настроить заново" && sleep 2 && vmesscfadd
elif  [ "$menu" = "3" ]; then
readp "Введите свой оптимальный IP/домен：" menu
echo "$menu" > /etc/s-box/cfvmadd_argo.txt
green "Настройка выполнена успешно, выберите в главном меню пункт 9 для обновления конфигурации узлов" && sleep 2 && vmesscfadd
else
changeserv
fi
}

gitlabsub(){
echo
green "Убедитесь, что на сайте Gitlab уже создан проект, включена функция push и получен токен доступа"
yellow "1：Сбросить/задать ссылку подписки Gitlab"
yellow "0：Вернуться назад"
readp "Выберите【0-1】：" menu
if [ "$menu" = "1" ]; then
cd /etc/s-box
readp "Введите email для входа: " email
readp "Введите токен доступа: " token
readp "Введите имя пользователя: " userid
readp "Введите имя проекта: " project
echo
green "Для нескольких VPS можно использовать один токен и одно имя проекта, создавая несколько ссылок подписки через разные ветки"
green "Нажмите Enter, чтобы пропустить создание новой ветки и использовать только ссылку подписки основной ветки main (для первого VPS рекомендуется просто нажать Enter)"
readp "Название новой ветки: " gitlabml
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
git add sbox.json clmi.yaml jhsub.txt >/dev/null 2>&1
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
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/sbox.json/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/sing_box_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/clmi.yaml/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/clash_meta_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jhsub.txt/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/jh_sub_gitlab.txt
clsbshow
else
yellow "Не удалось настроить ссылку подписки Gitlab, пожалуйста, сообщите об ошибке"
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
git rm --cached sbox.json clmi.yaml jhsub.txt >/dev/null 2>&1
git commit -m "commit_rm_$(date +"%F %T")" >/dev/null 2>&1
git add sbox.json clmi.yaml jhsub.txt >/dev/null 2>&1
git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
chmod +x gitpush.sh
./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/s-box/gitlabtoken.txt >/dev/null 2>&1
clsbshow
else
yellow "Ссылка подписки Gitlab не настроена"
fi
cd
}

clsbshow(){
green "Текущие узлы Sing-box обновлены и отправлены"
green "Ссылка подписки Sing-box:"
blue "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
green "QR-код ссылки подписки Sing-box:"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "Текущая конфигурация узлов Mihomo обновлена и отправлена"
green "Ссылка подписки Mihomo:"
blue "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
green "QR-код ссылки подписки Mihomo:"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "Текущая конфигурация агрегированных узлов обновлена и отправлена"
green "Ссылка подписки:"
blue "$(cat /etc/s-box/jh_sub_gitlab.txt 2>/dev/null)"
echo
yellow "Можно открыть ссылку подписки в браузере и посмотреть содержимое конфигурации; если конфигурация отсутствует, проверьте настройки Gitlab и выполните сброс"
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
blue "Private_key приватный ключ：$pvk"
blue "Адрес IPV6：$v6"
blue "Значение reserved：$res"
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
green "Текущие изменяемые параметры warp-wireguard:"
green "Private_key приватный ключ：$wgprkey"
green "Адрес IPV6：$wgipv6"
green "Значение Reserved：$wgres"
green "IP удалённой стороны：$wgip:$wgpo"
echo
yellow "1：Сменить аккаунт warp-wireguard"
yellow "0：Вернуться назад"
readp "Выберите【0-1】：" menu
if [ "$menu" = "1" ]; then
green "Ниже приведён случайно сгенерированный обычный аккаунт warp-wireguard"
warpwg
echo
readp "Введите свой Private_key：" menu
sed -i "163s#$wgprkey#$menu#g" /etc/s-box/sb10.json
sed -i "132s#$wgprkey#$menu#g" /etc/s-box/sb11.json
readp "Введите свой адрес IPV6：" menu
sed -i "161s/$wgipv6/$menu/g" /etc/s-box/sb10.json
sed -i "130s/$wgipv6/$menu/g" /etc/s-box/sb11.json
readp "Введите своё значение Reserved (формат: число,число,число), если значения нет — Enter для пропуска：" menu
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
warp_s4_ip='Socks5-IPV4 не запущен, режим чёрного списка'
warp_s6_ip='Socks5-IPV6 не запущен, режим чёрного списка'
else
warp_s4_ip='Socks5-IPV4 доступен'
warp_s6_ip='Socks5-IPV6 самопроверка'
fi
v4v6
if [[ -z $v4 ]]; then
vps_ipv4='Локальный IPV4 отсутствует, режим чёрного списка'      
vps_ipv6="Текущий IP：$v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="Текущий IP：$v4"    
vps_ipv6="Текущий IP：$v6"
else
vps_ipv4="Текущий IP：$v4"    
vps_ipv6='Локальный IPV6 отсутствует, режим чёрного списка'
fi
unset swg4 swd4 swd6 swg6 ssd4 ssg4 ssd6 ssg6 sad4 sag4 sad6 sag6
wd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].domain_suffix | join(" ")')
wg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].geosite | join(" ")' 2>/dev/null)
if [[ "$wd4" == "yg_kkk" && ("$wg4" == "yg_kkk" || -z "$wg4") ]]; then
wfl4="${yellow}【warp outbound IPV4 доступен】без маршрутизации${plain}"
else
if [[ "$wd4" != "yg_kkk" ]]; then
swd4="$wd4 "
fi
if [[ "$wg4" != "yg_kkk" ]]; then
swg4=$wg4
fi
wfl4="${yellow}【warp outbound IPV4 доступен】маршрутизация включена：$swd4$swg4${plain} "
fi

wd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].domain_suffix | join(" ")')
wg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].geosite | join(" ")' 2>/dev/null)
if [[ "$wd6" == "yg_kkk" && ("$wg6" == "yg_kkk"|| -z "$wg6") ]]; then
wfl6="${yellow}【warp outbound IPV6 самопроверка】без маршрутизации${plain}"
else
if [[ "$wd6" != "yg_kkk" ]]; then
swd6="$wd6 "
fi
if [[ "$wg6" != "yg_kkk" ]]; then
swg6=$wg6
fi
wfl6="${yellow}【warp outbound IPV6 самопроверка】маршрутизация включена：$swd6$swg6${plain} "
fi

sd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].domain_suffix | join(" ")')
sg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].geosite | join(" ")' 2>/dev/null)
if [[ "$sd4" == "yg_kkk" && ("$sg4" == "yg_kkk" || -z "$sg4") ]]; then
sfl4="${yellow}【$warp_s4_ip】без маршрутизации${plain}"
else
if [[ "$sd4" != "yg_kkk" ]]; then
ssd4="$sd4 "
fi
if [[ "$sg4" != "yg_kkk" ]]; then
ssg4=$sg4
fi
sfl4="${yellow}【$warp_s4_ip】маршрутизация включена：$ssd4$ssg4${plain} "
fi

sd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].domain_suffix | join(" ")')
sg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].geosite | join(" ")' 2>/dev/null)
if [[ "$sd6" == "yg_kkk" && ("$sg6" == "yg_kkk" || -z "$sg6") ]]; then
sfl6="${yellow}【$warp_s6_ip】без маршрутизации${plain}"
else
if [[ "$sd6" != "yg_kkk" ]]; then
ssd6="$sd6 "
fi
if [[ "$sg6" != "yg_kkk" ]]; then
ssg6=$sg6
fi
sfl6="${yellow}【$warp_s6_ip】маршрутизация включена：$ssd6$ssg6${plain} "
fi

ad4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].domain_suffix | join(" ")' 2>/dev/null)
ag4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].geosite | join(" ")' 2>/dev/null)
if [[ ("$ad4" == "yg_kkk" || -z "$ad4") && ("$ag4" == "yg_kkk" || -z "$ag4") ]]; then
adfl4="${yellow}【$vps_ipv4】без маршрутизации${plain}" 
else
if [[ "$ad4" != "yg_kkk" ]]; then
sad4="$ad4 "
fi
if [[ "$ag4" != "yg_kkk" ]]; then
sag4=$ag4
fi
adfl4="${yellow}【$vps_ipv4】маршрутизация включена：$sad4$sag4${plain} "
fi

ad6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].domain_suffix | join(" ")' 2>/dev/null)
ag6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].geosite | join(" ")' 2>/dev/null)
if [[ ("$ad6" == "yg_kkk" || -z "$ad6") && ("$ag6" == "yg_kkk" || -z "$ag6") ]]; then
adfl6="${yellow}【$vps_ipv6】без маршрутизации${plain}" 
else
if [[ "$ad6" != "yg_kkk" ]]; then
sad6="$ad6 "
fi
if [[ "$ag6" != "yg_kkk" ]]; then
sag6=$ag6
fi
adfl6="${yellow}【$vps_ipv6】маршрутизация включена：$sad6$sag6${plain} "
fi
}

changefl(){
sbactive
blue "Выполнить единую доменную маршрутизацию для всех протоколов"
blue "Чтобы маршрутизация работала корректно, для двухстекового IP (IPV4/IPV6) используется приоритетный режим"
blue "warp-wireguard включён по умолчанию (пункты 1 и 2)"
blue "Для socks5 на VPS нужно установить официальный клиент warp или WARP-plus-Socks5-赛风VPN (пункты 3 и 4)"
blue "Маршрутизация через локальный исходящий трафик VPS (пункты 5 и 6)"
echo
[[ "$sbnh" == "1.10" ]] && blue "Текущее ядро Sing-box поддерживает способ маршрутизации geosite" || blue "Текущее ядро Sing-box не поддерживает способ маршрутизации geosite, доступны только пункты 2、3、5、6"
echo
yellow "Внимание："
yellow "1. В режиме полного домена можно указывать только полный домен (пример: для Google указывать：www.google.com)"
yellow "2. В режиме geosite нужно указывать имя правила geosite (пример: Netflix：netflix；Disney：disney；ChatGPT：openai；глобально с обходом Китая：geolocation-!cn)"
yellow "3. Один и тот же полный домен или geosite нельзя маршрутизировать повторно"
yellow "4. Если в канале маршрутизации один из каналов не имеет сети, указанная маршрутизация будет работать как чёрный список, то есть доступ к сайту будет заблокирован"
changef
}

changef(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sbymfl
echo
[[ "$sbnh" != "1.10" ]] && wfl4='пока не поддерживается' sfl6='пока не поддерживается' adfl4='пока не поддерживается' adfl6='пока не поддерживается'
green "1：Сбросить домены маршрутизации warp-wireguard-ipv4 с приоритетом $wfl4"
green "2：Сбросить домены маршрутизации warp-wireguard-ipv6 с приоритетом $wfl6"
green "3：Сбросить домены маршрутизации warp-socks5-ipv4 с приоритетом $sfl4"
green "4：Сбросить домены маршрутизации warp-socks5-ipv6 с приоритетом $sfl6"
green "5：Сбросить домены маршрутизации через локальный VPS ipv4 с приоритетом $adfl4"
green "6：Сбросить домены маршрутизации через локальный VPS ipv6 с приоритетом $adfl6"
green "0：Вернуться назад"
echo
readp "Выберите：" menu

if [ "$menu" = "1" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：Использовать режим полного домена\n2：Использовать режим geosite\n3：Вернуться назад\nВыберите：" menu
if [ "$menu" = "1" ]; then
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации полного домена для warp-wireguard-ipv4：" w4flym
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
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации geosite для warp-wireguard-ipv4：" w4flym
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
yellow "К сожалению! Сейчас поддерживается только warp-wireguard-ipv6. Если нужен warp-wireguard-ipv4, переключитесь на ядро серии 1.10" && exit
fi

elif [ "$menu" = "2" ]; then
readp "1：Использовать режим полного домена\n2：Использовать режим geosite\n3：Вернуться назад\nВыберите：" menu
if [ "$menu" = "1" ]; then
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации полного домена для warp-wireguard-ipv6：" w6flym
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
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации geosite для warp-wireguard-ipv6：" w6flym
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
yellow "К сожалению! Текущее ядро Sing-box не поддерживает способ маршрутизации geosite. Для поддержки переключитесь на ядро серии 1.10" && exit
fi
else
changef
fi

elif [ "$menu" = "3" ]; then
readp "1：Использовать режим полного домена\n2：Использовать режим geosite\n3：Вернуться назад\nВыберите：" menu
if [ "$menu" = "1" ]; then
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации полного домена для warp-socks5-ipv4：" s4flym
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
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации geosite для warp-socks5-ipv4：" s4flym
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
yellow "К сожалению! Текущее ядро Sing-box не поддерживает способ маршрутизации geosite. Для поддержки переключитесь на ядро серии 1.10" && exit
fi
else
changef
fi

elif [ "$menu" = "4" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：Использовать режим полного домена\n2：Использовать режим geosite\n3：Вернуться назад\nВыберите：" menu
if [ "$menu" = "1" ]; then
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации полного домена для warp-socks5-ipv6：" s6flym
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
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации geosite для warp-socks5-ipv6：" s6flym
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
yellow "К сожалению! Сейчас поддерживается только warp-socks5-ipv4. Если нужен warp-socks5-ipv6, переключитесь на ядро серии 1.10" && exit
fi

elif [ "$menu" = "5" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：Использовать режим полного домена\n2：Использовать режим geosite\n3：Вернуться назад\nВыберите：" menu
if [ "$menu" = "1" ]; then
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации полного домена для локального VPS ipv4：" ad4flym
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
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации geosite для локального VPS ipv4：" ad4flym
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
yellow "К сожалению! Текущее ядро Sing-box не поддерживает способ маршрутизации geosite. Для поддержки переключитесь на ядро серии 1.10" && exit
fi
else
changef
fi
else
yellow "К сожалению! Если нужна маршрутизация через локальный VPS ipv4, переключитесь на ядро серии 1.10" && exit
fi

elif [ "$menu" = "6" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：Использовать режим полного домена\n2：Использовать режим geosite\n3：Вернуться назад\nВыберите：" menu
if [ "$menu" = "1" ]; then
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации полного домена для локального VPS ipv6：" ad6flym
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
readp "Укажите домены через пробел, Enter — сбросить и очистить канал маршрутизации geosite для локального VPS ipv6：" ad6flym
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
yellow "К сожалению! Текущее ядро Sing-box не поддерживает способ маршрутизации geosite. Для поддержки переключитесь на ядро серии 1.10" && exit
fi
else
changef
fi
else
yellow "К сожалению! Если нужна маршрутизация через локальный VPS ipv6, переключитесь на ядро серии 1.10" && exit
fi
else
sb
fi
}

restartsb(){
if command -v apk >/dev/null 2>&1; then
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
readp "1：Перезапустить\n2：Остановить\nВыберите：" menu
if [ "$menu" = "1" ]; then
restartsb
sbactive
green "Служба Sing-box перезапущена\n" && sleep 3 && sb
elif [ "$menu" = "2" ]; then
if command -v apk >/dev/null 2>&1; then
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
sed -i '/sbwpph/d' /tmp/crontab.tmp
sed -i '/url http/d' /tmp/crontab.tmp
sed -i '/websbox/d' /tmp/crontab.tmp
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
red "Sing-box-yg установлен некорректно" && exit
fi
lnsb
curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
green "Скрипт установки Sing-box-yg успешно обновлён" && sleep 5 && sb
}

lapre(){
json=$(curl -Ls --max-time 3 https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box)
if echo "$json"|grep -q '"versions"'; then
latcore=$(echo "$json"|grep -Eo '"[0-9.]+",'|head -n1|tr -d '",')
precore=$(echo "$json"|grep -Eo '"[0-9.]*-[^"]*"'|head -n1|tr -d '",')
else
page=$(curl -Ls --max-time 3 https://github.com/SagerNet/sing-box/releases)
latcore=$(echo "$page"|grep -oE 'tag/v[0-9.]+'|head -n1|cut -d'v' -f2)
precore=$(echo "$page"|grep -oE '/tag/v[0-9.]+-[^"]+'|head -n1|cut -d'v' -f2)
fi
inscore=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')
}

upsbcroe(){
sbactive
lapre
[[ $inscore =~ ^[0-9.]+$ ]] && lat="【установлен v$inscore】" || pre="【установлен v$inscore】"
green "1：Обновить/переключить на последнюю стабильную версию Sing-box v$latcore  ${bblue}${lat}${plain}"
green "2：Обновить/переключить на последнюю тестовую версию Sing-box v$precore  ${bblue}${pre}${plain}"
green "3：Переключить Sing-box на конкретную стабильную или тестовую версию, нужно указать номер версии (рекомендуется версия 1.10.0 и выше)"
green "0：Вернуться назад"
readp "Выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
upcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases/latest | grep -oP 'tag/v\K[0-9.]+' | head -n 1)
elif [ "$menu" = "2" ]; then
upcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases | grep -oP '/tag/v\K[0-9.]+-[^"]+' | head -n 1)
elif [ "$menu" = "3" ]; then
echo
red "Внимание: номер версии можно посмотреть на https://github.com/SagerNet/sing-box/tags, при этом должна быть надпись Downloads (обязательно версия серии 1.10 или 1.30 и выше)"
green "Формат стабильной версии：число.число.число (пример：1.10.7   внимание, ядро серии 1.10 поддерживает маршрутизацию geosite, ядра выше 1.10 не поддерживают geosite"
green "Формат тестовой версии：число.число.число-alpha или rc или beta.число (пример：1.13.0-alpha или rc или beta.1)"
readp "Введите версию Sing-box：" upcore
else
sb
fi
if [[ -n $upcore ]]; then
green "Начинается загрузка и обновление ядра Sing-box……подождите"
sbname="sing-box-$upcore-linux-$cpu"
curl -L -o /etc/s-box/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$upcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb && sbshare > /dev/null 2>&1
blue "Успешно обновлено/переключено ядро Sing-box до версии：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')" && sleep 3 && sb
else
red "Ядро Sing-box загружено не полностью, установка не удалась, попробуйте ещё раз" && upsbcroe
fi
else
red "Не удалось загрузить ядро Sing-box или версия не существует, попробуйте ещё раз" && upsbcroe
fi
else
red "Ошибка определения версии, попробуйте ещё раз" && upsbcroe
fi
}

unins(){
if command -v apk >/dev/null 2>&1; then
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
ps -ef | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json 2>/dev/null | jq -r '.inbounds[1].listen_port')" | awk '{print $2}' | xargs kill 2>/dev/null
ps -ef | grep '[s]bwpph' | awk '{print $2}' | xargs kill 2>/dev/null
kill -15 $(pgrep -f 'websbox' 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box sbyg_update /usr/bin/sb /root/geoip.db /root/geosite.db /root/warpapi /root/warpip /root/websbox
rm -f /etc/local.d/alpineargo.start /etc/local.d/alpinesub.start /etc/local.d/alpinews5.start
uncronsb
iptables -t nat -F PREROUTING >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
green "Удаление Sing-box завершено!"
blue "Добро пожаловать снова в скрипт Sing-box-yg：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)"
echo
}

sblog(){
red "Выход из логов Ctrl+c"
if command -v apk >/dev/null 2>&1; then
yellow "Просмотр логов в alpine пока не поддерживается"
else
#systemctl status sing-box
journalctl -u sing-box.service -o cat -f
fi
}

sbactive(){
if [[ ! -f /etc/s-box/sb.json ]]; then
red "Sing-box запущен некорректно, удалите и установите заново либо выберите пункт 10 для просмотра логов и отправки обратной связи" && exit
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
echo "$v2sub" > /etc/s-box/jhsub.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Агрегированные узлы 】информация об узлах ниже：" && sleep 2
echo
echo "Ссылка для分享"
echo -e "${yellow}$v2sub${plain}"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
sb_client
}

clash_sb_share(){
sbactive
echo
yellow "1：Обновить и показать ссылки каждого протокола, QR-коды и агрегированные узлы"
yellow "2：Обновить и показать тройную конфигурацию клиентов Mihomo、Sing-box SFA/SFI/SFW, а также приватные ссылки подписки Gitlab"
yellow "3：Отправить актуальную конфигурацию узлов (пункт 1 + пункт 2) в уведомление Telegram"
yellow "0：Вернуться назад"
readp "Выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
sbshare
elif  [ "$menu" = "2" ]; then
green "Пожалуйста, подождите……"
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "Ссылки подписки Gitlab ниже："
gitlabsubgo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀Ниже отображён конфигурационный файл Mihomo："
red "Путь к файлу /etc/s-box/clmi.yaml，при самостоятельном копировании ориентируйтесь на формат yaml" && sleep 2
echo
cat /etc/s-box/clmi.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀Ниже отображён конфигурационный файл SFA/SFI/SFW："
red "Android SFA、Apple SFI，официальный пакет SFW для Windows можно скачать самостоятельно из проекта Yongge на Github，"
red "Путь к файлу /etc/s-box/sbox.json，при самостоятельном копировании ориентируйтесь на формат json" && sleep 2
echo
cat /etc/s-box/sbox.json
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
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
}
cfwarp(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh)
}
bbr(){
if [[ $vi =~ lxc|openvz ]]; then
yellow "Текущая архитектура VPS — $vi, включение оригинального ускорения BBR не поддерживается" && sleep 2 && exit 
else
green "Нажмите любую клавишу, чтобы включить ускорение BBR, ctrl+c — выход"
bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
fi
}

showprotocol(){
allports
sbymfl
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run' || ps -ef 2>/dev/null | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" >/dev/null 2>&1; then
vm_zs="TLS отключён"
argoym="включён"
else
vm_zs="TLS отключён"
argoym="не включён"
fi
else
vm_zs="TLS включён"
argoym="включение не поддерживается"
fi
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_zs="самоподписанный сертификат" || hy2_zs="доменный сертификат"
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_zs="самоподписанный сертификат" || tu5_zs="доменный сертификат"
an_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
[[ "$an_sniname" = '/etc/s-box/private.key' ]] && an_zs="самоподписанный сертификат" || an_zs="доменный сертификат"
echo -e "Ключевая информация по узлам Sing-box и список доменов с маршрутизацией:"
echo -e "🚀【 Vless-reality 】${yellow}порт:$vl_port  адрес маскировки сертификата Reality-домена：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')${plain}"
if [[ "$tls" = "false" ]]; then
echo -e "🚀【   Vmess-ws    】${yellow}порт:$vm_port   тип сертификата:$vm_zs   статус Argo:$argoym${plain}"
else
echo -e "🚀【 Vmess-ws-tls  】${yellow}порт:$vm_port   тип сертификата:$vm_zs   статус Argo:$argoym${plain}"
fi
echo -e "🚀【  Hysteria-2   】${yellow}порт:$hy2_port  тип сертификата:$hy2_zs  дополнительные порты переадресации: $hy2zfport${plain}"
echo -e "🚀【    Tuic-v5    】${yellow}порт:$tu5_port  тип сертификата:$tu5_zs  дополнительные порты переадресации: $tu5zfport${plain}"
if [[ "$sbnh" != "1.10" ]]; then
echo -e "🚀【    Anytls     】${yellow}порт:$an_port  тип сертификата:$an_zs${plain}"
fi
if [ -s /etc/s-box/subport.log ]; then
showsubport=$(cat /etc/s-box/subport.log)
if ps -ef 2>/dev/null | grep "$showsubport" | grep -v grep >/dev/null; then
showsubtoken=$(cat /etc/s-box/subtoken.log 2>/dev/null)
subip=$(cat /etc/s-box/server_ip.log 2>/dev/null)
suburl="$subip:$showsubport/$showsubtoken"
echo "Локальный IP-адрес подписки Clash/Mihomo：http://$suburl/clmi.yaml"
echo "Локальный IP-адрес подписки Sing-box：http://$suburl/sbox.json"
echo "Локальный IP-адрес подписки агрегированных протоколов：http://$suburl/jhsub.txt"
fi
fi
if [ "$argoym" = "включён" ]; then
#echo -e "Vmess-UUID：${yellow}$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')${plain}"
#echo -e "Vmess-Path：${yellow}$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')${plain}"
if ps -ef 2>/dev/null | grep "[l]ocalhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" >/dev/null 2>&1; then
echo -e "Временный домен Argo：${yellow}$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')${plain}"
fi
if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
echo -e "Постоянный домен Argo：${yellow}$(cat /etc/s-box/sbargoym.log 2>/dev/null)${plain}"
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
grep -q "country" /etc/s-box/sbwpph.log 2>/dev/null && s5ms="Режим прокси Psiphon WARP-plus-Socks5 с несколькими регионами (порт:$s5port  страна:$showgj)" || s5ms="Режим локального прокси Warp (порт:$s5port)"
echo -e "Статус WARP-plus-Socks5：$yellowзапущен $s5ms$plain"
else
echo -e "Статус WARP-plus-Socks5：$yellowне запущен$plain"
fi
echo "------------------------------------------------------------------------------------"
ww4="Домены маршрутизации warp-wireguard-ipv4 с приоритетом：$wfl4"
ww6="Домены маршрутизации warp-wireguard-ipv6 с приоритетом：$wfl6"
ws4="Домены маршрутизации warp-socks5-ipv4 с приоритетом：$sfl4"
ws6="Домены маршрутизации warp-socks5-ipv6 с приоритетом：$sfl6"
l4="Домены маршрутизации локального VPS ipv4 с приоритетом：$adfl4"
l6="Домены маршрутизации локального VPS ipv6 с приоритетом：$adfl6"
[[ "$sbnh" == "1.10" ]] && ymflzu=("ww4" "ww6" "ws4" "ws6" "l4" "l6") || ymflzu=("ww6" "ws4" "l4" "l6")
for ymfl in "${ymflzu[@]}"; do
if [[ ${!ymfl} != *"未"* ]]; then
echo -e "${!ymfl}"
fi
done
if [[ $ww4 = *"未"* && $ww6 = *"未"* && $ws4 = *"未"* && $ws6 = *"未"* && $l4 = *"未"* && $l6 = *"未"* ]] ; then
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
ps -ef | grep '[s]bwpph' | awk '{print $2}' | xargs kill 2>/dev/null
v4v6
if [[ -n $v4 ]]; then
sw46=4
else
red "IPV4 отсутствует, убедитесь, что установлен режим WARP-IPV4"
sw46=6
fi
echo
readp "Задайте порт WARP-plus-Socks5 (Enter — порт по умолчанию 40000)：" port
if [[ -z $port ]]; then
port=40000
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nПорт занят, введите порт заново" && readp "Пользовательский порт:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nПорт занят, введите порт заново" && readp "Пользовательский порт:" port
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
ps -ef | grep '[s]bwpph' | awk '{print $2}' | xargs kill 2>/dev/null
rm -rf /etc/s-box/sbwpph.log
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbwpph/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
rm -rf /etc/local.d/alpinews5.start
}
aplws5(){
if command -v apk >/dev/null 2>&1; then
cat > /etc/local.d/alpinews5.start <<'EOF'
#!/bin/bash
sleep 10
nohup $(cat /etc/s-box/sbwpph.log 2>/dev/null)
EOF
chmod +x /etc/local.d/alpinews5.start
rc-update add local default >/dev/null 2>&1
else
crontab -l 2>/dev/null > /tmp/crontab.tmp
sed -i '/sbwpph/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup $(cat /etc/s-box/sbwpph.log 2>/dev/null) &"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
fi
}
echo
yellow "1：Сбросить и включить режим локального Warp-прокси WARP-plus-Socks5"
yellow "2：Сбросить и включить режим многорегионального прокси Psiphon WARP-plus-Socks5"
yellow "3：Остановить режим прокси WARP-plus-Socks5"
yellow "0：Вернуться назад"
readp "Выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
ins
nohup /etc/s-box/sbwpph -b 127.0.0.1:$port --gool -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 &
green "Получение IP……пожалуйста, подождите……" && sleep 20
resv1=$(curl -sm3 --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sm3 -x socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "Не удалось получить IP для WARP-plus-Socks5" && unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --gool -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > /etc/s-box/sbwpph.log
aplws5
green "IP для WARP-plus-Socks5 успешно получен, можно использовать маршрутизацию через Socks5"
fi
elif [ "$menu" = "2" ]; then
ins
echo '
Австрия（AT）
Австралия（AU）
Бельгия（BE）
Болгария（BG）
Канада（CA）
Швейцария（CH）
Чехия (CZ)
Германия（DE）
Дания（DK）
Эстония（EE）
Испания（ES）
Финляндия（FI）
Франция（FR）
Великобритания（GB）
Хорватия（HR）
Венгрия (HU)
Ирландия（IE）
Индия（IN）
Италия (IT)
Япония（JP）
Литва（LT）
Латвия（LV）
Нидерланды（NL）
Норвегия (NO)
Польша（PL）
Португалия（PT）
Румыния (RO)
Сербия（RS）
Швеция（SE）
Сингапур (SG)
Словакия（SK）
США（US）
'
readp "Выберите страну/регион (введите две заглавные буквы в конце, например для США — US)：" guojia
nohup /etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 &
green "Получение IP……пожалуйста, подождите……" && sleep 20
resv1=$(curl -sm3 --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sm3 -x socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "Не удалось получить IP для WARP-plus-Socks5, попробуйте выбрать другую страну/регион" && unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > /etc/s-box/sbwpph.log
aplws5
green "IP для WARP-plus-Socks5 успешно получен, можно использовать маршрутизацию через Socks5"
fi
elif [ "$menu" = "3" ]; then
unins && green "Функция прокси WARP-plus-Socks5 остановлена"
else
sb
fi
}

sbsm(){
echo
green "Подпишитесь на YouTube-канал Yongge：https://youtube.com/@ygkkk?sub_confirmation=1 — там свежая информация о новых прокси-протоколах и динамике обхода блокировок"
echo
blue "Видеоуроки по скрипту sing-box-yg：https://www.youtube.com/playlist?list=PLMgly2AulGG_Affv6skQXWnVqw7XWiPwJ"
echo
blue "Описание скрипта sing-box-yg в блоге：http://ygkkk.blogspot.com/2023/10/sing-box-yg.html"
echo
blue "Адрес проекта скрипта sing-box-yg：https://github.com/yonggekkk/sing-box-yg"
echo
blue "Рекомендуемая новинка от Yongge：ArgoSBX — однокнопочный безинтерактивный скрипт-малыш"
blue "Адрес проекта ArgoSBX：https://github.com/yonggekkk/argosbx"
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
white "Github-проект Yongge  ：github.com/yonggekkk"
white "Блог Yongge на Blogger ：ygkkk.blogspot.com"
white "YouTube-канал Yongge ：www.youtube.com/@ygkkk"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "Скрипт совместного сосуществования пяти протоколов: Vless-reality-vision、Vmess-ws(tls)+Argo、Hy2、Tuic、Anytls"
white "Быстрая команда скрипта：sb"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. Установить Sing-box в один клик" 
green " 2. Удалить Sing-box"
white "----------------------------------------------------------------------------------"
green " 3. Изменить конфигурацию 【двойной сертификат TLS/UUID путь/Argo/IP приоритет/TG уведомления/Warp/подписка/CDN-оптимизация】" 
green " 4. Изменить основной порт/добавить мультипортовое прыжковое переиспользование" 
green " 5. Маршрутизация доменов по трём каналам"
green " 6. Остановить/перезапустить Sing-box"   
green " 7. Обновить скрипт Sing-box-yg"
green " 8. Обновить/переключить/указать версию ядра Sing-box"
white "----------------------------------------------------------------------------------"
green " 9. Обновить и показать узлы 【Mihomo/SFA+SFI+SFW три-в-одном конфиг/ссылки подписки/отправка уведомления в TG】"
green "10. Просмотреть журнал работы Sing-box"
green "11. Включить оригинальный BBR+FQ в один клик"
green "12. Управление выпуском доменного сертификата Acme"
green "13. Управление Warp и просмотр статуса разблокировки Netflix/ChatGPT"
green "14. Добавить режим прокси WARP-plus-Socks5 【локальный Warp/многорегиональный Psiphon-VPN】"
green "15. Обновить локальный IP и скорректировать вывод конфигурации IPV4/IPV6"
white "----------------------------------------------------------------------------------"
green "16. Руководство по использованию скрипта Sing-box-yg"
white "----------------------------------------------------------------------------------"
green " 0. Выйти из скрипта"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
insV=$(cat /etc/s-box/v 2>/dev/null)
latestV=$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1)
if [ -f /etc/s-box/v ]; then
if [ "$insV" = "$latestV" ]; then
echo -e "Текущая последняя версия скрипта Sing-box-yg：${bblue}${insV}${plain} (установлена)"
else
echo -e "Текущая версия скрипта Sing-box-yg：${bblue}${insV}${plain}"
echo -e "Обнаружена новая версия скрипта Sing-box-yg：${yellow}${latestV}${plain} (можно выбрать 7 для обновления)"
echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version)${plain}"
fi
else
echo -e "Текущая версия скрипта Sing-box-yg：${bblue}${latestV}${plain}"
yellow "Скрипт Sing-box-yg не установлен! Сначала выберите 1 для установки"
fi

lapre
if [ -f '/etc/s-box/sb.json' ]; then
if [[ $inscore =~ ^[0-9.]+$ ]]; then
if [ "${inscore}" = "${latcore}" ]; then
echo
echo -e "Текущее последнее стабильное ядро Sing-box：${bblue}${inscore}${plain} (установлено)"
echo
echo -e "Текущее последнее тестовое ядро Sing-box：${bblue}${precore}${plain} (можно переключить)"
else
echo
echo -e "Сейчас установлено стабильное ядро Sing-box：${bblue}${inscore}${plain}"
echo -e "Обнаружено новое стабильное ядро Sing-box：${yellow}${latcore}${plain} (можно выбрать 8 для обновления)"
echo
echo -e "Текущее последнее тестовое ядро Sing-box：${bblue}${precore}${plain} (можно переключить)"
fi
else
if [ "${inscore}" = "${precore}" ]; then
echo
echo -e "Текущее последнее тестовое ядро Sing-box：${bblue}${inscore}${plain} (установлено)"
echo
echo -e "Текущее последнее стабильное ядро Sing-box：${bblue}${latcore}${plain} (можно переключить)"
else
echo
echo -e "Сейчас установлено тестовое ядро Sing-box：${bblue}${inscore}${plain}"
echo -e "Обнаружено новое тестовое ядро Sing-box：${yellow}${precore}${plain} (можно выбрать 8 для обновления)"
echo
echo -e "Текущее последнее стабильное ядро Sing-box：${bblue}${latcore}${plain} (можно переключить)"
fi
fi
else
echo
echo -e "Текущее последнее стабильное ядро Sing-box：${bblue}${latcore}${plain}"
echo -e "Текущее последнее тестовое ядро Sing-box：${bblue}${precore}${plain}"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "Текущее состояние VPS:"
echo -e "Система:$blue$op$plain  \c";echo -e "Ядро:$blue$version$plain  \c";echo -e "Процессор:$blue$cpu$plain  \c";echo -e "Виртуализация:$blue$vi$plain  \c";echo -e "Алгоритм BBR:$blue$bbr$plain"
v4v6
if [[ "$v6" == "2a09"* ]]; then
w6="【WARP】"
fi
if [[ "$v4" == "104.28"* ]]; then
w4="【WARP】"
fi
[[ -z $v4 ]] && showv4='Адрес IPV4 потерян, переключитесь на IPV6 или переустановите Sing-box' || showv4=$v4$w4
[[ -z $v6 ]] && showv6='Адрес IPV6 потерян, переключитесь на IPV4 или переустановите Sing-box' || showv6=$v6$w6
if [[ -z $v4 ]]; then
vps_ipv4='Нет IPV4'      
vps_ipv6="$v6"
location="$v6dq"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="$v4"    
vps_ipv6="$v6"
location="$v4dq"
else
vps_ipv4="$v4"    
vps_ipv6='Нет IPV6'
location="$v4dq"
fi
echo -e "Локальный адрес IPV4：$blue$vps_ipv4$w4$plain   Локальный адрес IPV6：$blue$vps_ipv6$w6$plain"
echo -e "Регион сервера：$blue$location$plain"
if [[ "$sbnh" == "1.10" ]]; then
rpip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[0].domain_strategy') 2>/dev/null
if [[ $rpip = 'prefer_ipv6' ]]; then
v4_6="Исходящий трафик с приоритетом IPV6($showv6)"
elif [[ $rpip = 'prefer_ipv4' ]]; then
v4_6="Исходящий трафик с приоритетом IPV4($showv4)"
elif [[ $rpip = 'ipv4_only' ]]; then
v4_6="Только исходящий IPV4($showv4)"
elif [[ $rpip = 'ipv6_only' ]]; then
v4_6="Только исходящий IPV6($showv6)"
fi
echo -e "Приоритет прокси-IP：$blue$v4_6$plain"
fi
if command -v apk >/dev/null 2>&1; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl is-active sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Статус Sing-box：$blueработает$plain"
elif [[ -z $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Статус Sing-box：$yellowне запущен, выберите 10 для просмотра логов и отправки обратной связи; рекомендуется переключиться на стабильное ядро или удалить и переустановить скрипт$plain"
else
echo -e "Статус Sing-box：$redне установлен$plain"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
if [ -f '/etc/s-box/sb.json' ]; then
showprotocol
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
readp "Введите число【0-16】:" Input
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
