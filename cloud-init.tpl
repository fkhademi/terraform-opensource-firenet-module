#!/bin/bash
# 
# Download and install a Ubuntu Firewall with a preconfigured ELK dashboard to show firewall logs
#
# Inputs: ${hostname} ${domainname} ${gw_lan_ip}
 
LOG=/home/ubuntu/log

# Remove apache2
echo "$(date) [INFO] Starting cloud init .." >> $LOG
sudo apt autoremove -y
sudo apt-get remove apache2 -y
sudo add-apt-repository universe
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
echo "[INFO] $(date) Running apt-get to get all the packages" >> $LOG
apt-get install -y nginx ifupdown net-tools gufw elasticsearch kibana logstash filebeat 

# Nginx config - SSL redirect
echo "server {
    listen 80;
    server_name ${hostname};
	location / {
        proxy_pass http://localhost:8080/guacamole/;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_cookie_path /guacamole/ /;
    }
}
server {
    listen 81;
    server_name ${hostname};
	location / {
        proxy_pass http://localhost:9200/;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_cookie_path / /;
    }
}
server {
    listen 82;
    server_name ${hostname};
	location / {
        proxy_pass http://localhost:5601/;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_cookie_path / /;
    }
}" | sudo tee -a /etc/nginx/conf.d/default.conf

sudo systemctl start nginx 
sudo systemctl enable nginx
sudo service nginx restart

echo "$(date) [INFO] configured and started nginx .." >> $LOG

# Add pod ID search domain
sudo sed -i '$d' /etc/netplan/50-cloud-init.yaml 
echo "            nameservers:
                search: [${domainname}]" | sudo tee -a /etc/netplan/50-cloud-init.yaml
sudo netplan apply

###

echo "[INFO] $(date) Adding interfaces to netplan" >> $LOG
sudo sed -i '$ d' /etc/netplan/50-cloud-init.yaml
sudo tee -a /etc/netplan/50-cloud-init.yaml > /dev/null <<EOT
                addresses:
                - 1.1.1.1
                - 8.8.8.8
        ens6:
            dhcp4: true
            dhcp4-overrides:
              use-routes: false            
            routes:
            - to: 10.0.0.0/8
              via: ${gw_lan_ip}
    version: 2
EOT

echo "[INFO] $(date) Restarting netplan" >> $LOG
sudo netplan apply

echo "[INFO] $(date) Adding IP Fowarding" >> $LOG

sudo sed -i 's/#net\/ipv4\/ip_forward=1/net\/ipv4\/ip_forward=1/g' /etc/ufw/sysctl.conf
sudo sed -i '1i\*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.0.0.0\/8 -o ens5 -j MASQUERADE\nCOMMIT' /etc/ufw/before.rules

sudo ufw reload

sudo ufw allow from 0.0.0.0/0 to any port 22
sudo ufw allow from 0.0.0.0/0 to any port 80
sudo ufw allow from 0.0.0.0/0 to any port 81
sudo ufw allow from 0.0.0.0/0 to any port 82
#sudo ufw default allow routed
sudo ufw default deny routed
#sudo ufw route allow in on ens7 out  on  ens7 from 10.0.0.0/8
#sudo ufw route deny in on ens7 out  on  ens7 from 10.0.0.0/8 to port 80
sudo ufw route deny in on ens6 out on ens6 log-all from 10.0.0.0/8 to 10.0.0.0/8 port 80
sudo ufw route allow in on ens6 out on ens6 log-all from 10.0.0.0/8 to 10.0.0.0/8 port 22
sudo ufw route allow in on ens6 out on ens6 log-all from 10.0.0.0/8 to 10.0.0.0/8 port 443
sudo ufw route allow in on ens6 out on ens5 log-all from 10.0.0.0/8 to 0.0.0.0/0 port 443
sudo ufw enable
sudo ufw logging low

echo "[INFO] $(date) Added some firewall rules" >> $LOG


# ## ELK

echo "[INFO] $(date) Cofniguring Elastic and Kibana" >> $LOG

sudo sed -i 's/#network.host: 192.168.0.1/network.host: localhost/g' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/#kibana.defaultAppId: \"home\"/kibana.defaultAppId: \"dashboard\/72f30ea0-00f2-11ec-9ddf-276e9b55d2a3\"/g' /etc/kibana/kibana.yml
sudo sed -i "s/#server.publicBaseUrl: \"\"/server.publicBaseUrl: \"http:\/\/${hostname}\"/g" /etc/kibana/kibana.yml
echo "telemetry.enabled: false" | sudo tee -a /etc/kibana/kibana.yml
echo "security.showInsecureClusterWarning: false" | sudo tee -a /etc/kibana/kibana.yml

echo "[INFO] $(date) Starting Elastic and Kibana" >> $LOG

sudo systemctl start elasticsearch
sudo systemctl enable elasticsearch
sudo systemctl enable kibana
sudo systemctl start kibana

echo "[INFO] $(date) Configuring Filebeat" >> $LOG

echo "input {
  beats {
    port => 5044
  }
}
" | sudo tee -a /etc/logstash/conf.d/02-beats-input.conf

echo "output {
  if [@metadata][pipeline] {
    elasticsearch {
    hosts => [\"localhost:9200\"]
    manage_template => false
    index => \"%\{[@metadata][beat]\}-%\{[@metadata][version]\}-%\{+YYYY.MM.dd\}\"
    pipeline => \"%\{[@metadata][pipeline]\}\"
    }
  } else {
    elasticsearch {
    hosts => [\"localhost:9200\"]
    manage_template => false
    index => \"%\{[@metadata][beat]\}-%\{[@metadata][version]\}-%\{+YYYY.MM.dd\}\"
    }
  }
}" | sudo tee -a /etc/logstash/conf.d/30-elasticsearch-output.conf

sudo systemctl start logstash
sudo systemctl enable logstash

echo "[INFO] $(date) Starting Logstash" >> $LOG

sudo sed -i 's/output.elasticsearch/#output.elasticsearch/g' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/hosts: [\"localhost:9200\"]/#hosts: [\"localhost:9200\"]/g' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/#output.logstash:/output.logstash:/g' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/#hosts: [\"localhost:5044\"]/hosts: [\"localhost:5044\"]/g' /etc/elasticsearch/elasticsearch.yml

sed -i '11s/#var.paths:/var.paths: \[\"\/var\/log\/ufw.log\"\]/' /etc/filebeat/modules.d/system.yml.disabled
sed -i '15s/enabled: true/enabled: false/' /etc/filebeat/modules.d/system.yml.disabled

echo "[INFO] $(date) Finetuning the config" >> $LOG

sudo filebeat modules enable system
sudo filebeat setup --pipelines --modules system
sudo filebeat setup --index-management -E output.logstash.enabled=false -E 'output.elasticsearch.hosts=["localhost:9200"]'
sudo filebeat setup -E output.logstash.enabled=false -E output.elasticsearch.hosts=['localhost:9200'] -E setup.kibana.host=localhost:5601
sudo systemctl start filebeat
sudo systemctl enable filebeat

echo "[INFO] $(date) Started Filebeat" >> $LOG

# import kibana dashboard
echo "[INFO] $(date) Import index pattern to Kibana" >> $LOG
curl -d '{"attributes":{"fieldAttrs":"{}","title":"filebeat-7.14.0","timeFieldName":"@timestamp","fields":"[]","typeMeta":"{}","runtimeFieldMap":"{}"}}' -H "Content-Type: application/json" -H "kbn-xsrf: true" -X POST "http://localhost:82/api/saved_objects/index-pattern"

echo "[INFO] $(date) Download Kibana dashboard" >> $LOG
wget https://avx-build.s3.eu-central-1.amazonaws.com/dashboard.json -P /tmp/

sleep 10
echo "[INFO] $(date) Install Kibana Dashboard" >> $LOG
curl -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" -d @/tmp/dashboard.json "http://localhost:82/api/kibana/dashboards/import" >> $LOG

echo "[INFO] $(date) DONE" >> $LOG