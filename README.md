![k8s](https://github.com/alexandrdarkwind/TEST_K8S_Cluster/assets/123112359/d81ad552-aaab-4ef3-bb11-9019f62d5898)
<pre>
#Cначала развернем виртуальные сервера на hetzner cloud с помощу Terraform
#Для этого на hCloud https://console.hetzner.cloud/projects нужно создать новый проект 
#и сгенерировать для него https://console.hetzner.cloud/projects/$projects_id/security/tokens API Token.

#После этого копируем на рабочую машину с предустановленым Terraform

git clone https://github.com/alexandrdarkwind/TEST_K8S_Cluster.git
cd ./terraform

#Для сетапа серверов необходимо сразу создать приватный и публичные ssh ключи, переместив их в ./ssh_key под именами id_rsa и id_rsa.pub соответственно
#API Token можно как прописать в файле под "hcloud_token", так и экспортировать в переменную export HCLOUD_TOKEN= с консоли

#После качаем файлы провайдера и делаем проверку

terraform init
terraform plan

#Все настройки собрани в файле hetzner.tf.
#По умолчанию создаст 4 ноды с ресурсами cx21, изменить это можно в переменой "servers".
#Для дальнейших настроек по умолчанию 1-я нода расчитана как чистая машина, с которой можно провести все дальнейшие настройки кластера, а три оставшиеся непосредствено для развертивания k8s.

#После успешной проверки запускаем

terraform apply

#terraform кроме того что развернет 4 ноди с уже зарошеными на них публичными ключями, также проведет индексирование хедеров ядра
#apt-get update && apt-get install -y linux-headers-$(uname -r)
#что понадобиться для последующей настройки LINSTOR на серверах
</pre>
<pre>
cd ../
#k8s кластер будем розворачивать через ansible модулем kubespray
#Очень важно на машину с которой будет вестись установка заранее установить подходящие версии pyton pip и ansible (последний заранее можно не ставить)
#Версия pyton3 не ниже 3.9 а ansible-core==2.14.11
sudo apt-get update
sudo apt-get install pyton3.10
#если стояла более раняя версия pyton3 возможно прийдеться поменять симлинки перд дальнейшей установкой
python3.10 -m pip install --upgrade --force pip


wget https://github.com/kubernetes-sigs/kubespray/archive/refs/tags/v2.23.1.tar.gz
tar -xvf v2.23.1.tar.gz
cd kubespray
sudo pip install -r requirements.txt
#обязательно нужно убедиться что установился ansible-core --version не ниже 2.14.11, и при необходимости дополнительно переустановить pip install ansible-core==2.14.11

###
#редактируем ./inventory/sample/inventory.ini
#в меру ограниченых ресурсов будем использовать только 3 ноды
#которые одновременно будут мастерами и воркерами, а также etcd (при возможности лучше конечно воркеров вынести на отдельние физически сервера либо виртуалки)
#приводим до следующего вида (номерацию нод можно изменить, приводиться пример который был использован при последней сборке):
vin ./inventory/sample/inventory.ini
### Configure 'ip' variable to bind kubernetes services on a
### different ip than the default iface
### We should set etcd_member_name for etcd cluster. The node that is not a etcd member do not need to set the value, or can set the empty string value.
[all]
 node2 ansible_host=$IP_node1
 node3 ansible_host=$IP_node2
 node4 ansible_host=$IP_node3


### configure a bastion host if your nodes are not directly reachable
# [bastion]
# bastion ansible_host=x.x.x.x ansible_user=some_user

[kube_control_plane]
 node2
 node3
 node4

[etcd]
 node2
 node3
 node4

[kube_node]
 node2
 node3
 node4


[calico_rr]

[k8s_cluster:children]
kube_control_plane
kube_node
calico_rr
###
########################################

#редактируем ./inventory/sample/group_vars/k8s-cluster/addons.yml
#меняем значение на true для следующей[ строки:
helm_enabled: true # устанавливаем helm на ноды
#(остальное проще донастраивать потом)

#Начинаем процес установки
ansible-playbook -u root -i inventory/sample/inventory.ini cluster.yml -b

#Если процес установки прошел успешно, то можем зайти на первую по спику control_plane ноду и забрать файл конфигурации для подключения к кластеру через kubectl
#в директории /etc/kubernetes/
#если по какойто причине кластер был не инициализирован то возможно полуить конфиг с ключями и инструкции по команде
sudo kubeadm init

#если нужно посмотреть token уже после инициализации кластера, мо может помочь команада
kubeadm token list

#После получения файла конфига експортируем его для kubectl на рабочей машине с которой планируем работать с кластером
set KUBECONFIG=kubeconfig.conf
kubectl config view
</pre>
<pre>
#дальше можем начать уже настройки внутри кластера k8s

#Для дальнейших настроек нужно сменить директорию на скачанную (https://github.com/alexandrdarkwind/TEST_K8S_Cluster/kub-conf/)
cd ../kub-conf/


kubectl -apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

kubectl edit configmap -n kube-system kube-proxy
#для включения ARP выставляем значение strictARP: true

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml


#установка traefik 

helm repo add traefik https://helm.traefik.io/traefik
helm repo update

###
#cat ./traefik/values.yaml
deployment:
  replicas: 2
###


helm install traefik traefik/traefik --namespace traefik --create-namespace  -f /traefik/values.yaml
#также можно в формате через helm install traefik traefik/traefik --namespace traefik --create-namespace  -f - <<EOF
#deployment:
#  replicas: 2
#EOF

kubectl apply -f /traefik/traefik-configmap.yaml
</pre>
<pre>
#установка kubernetes-dashboard для проверки пробросов портов внутрь pods
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

###
#cat ./kubernetes-dashboard/kubernetes-dashboard-Ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
spec:
  ingressClassName: traefik
  rules:
  - host: test.test.com
    http:
      paths:
      - backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
        path: /
        pathType: ImplementationSpecific
###
</pre>
<pre>
#Установка LINSTOR через piraeus-operator

kubectl apply --server-side -k "https://github.com/piraeusdatastore/piraeus-operator//config/default?ref=v2.3.0"

#Создание Linstor Cluster
###
#cat ./piraeus-datastore/LinstorCluster.yaml
apiVersion: piraeus.io/v1
kind: LinstorCluster
metadata:
  name: linstorcluster
spec: {}
###

kubectl apply -f /piraeus-datastore/LinstorCluster.yaml

#Создание StorageClass (c 3-мя репликами хранилища)
###
#cat ./piraeus-datastore/StorageClass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: piraeus-storage-replicated
provisioner: linstor.csi.linbit.coms
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
parameters:
  linstor.csi.linbit.com/storagePool: pool1
  linstor.csi.linbit.com/placementCount: "3"
###

kubectl apply -f /piraeus-datastore/StorageClass.yaml

#делаем StorageClass по умолчанию
kubectl patch storageclass piraeus-storage-replicated -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
#либо через
#kubectl edit StorageClass
# добавляем вложеной стройчкой под annotations:
#storageclass.kubernetes.io/is-default-class: "true"
</pre>

<pre>
#установка postgres

###
#cat ./postgres/values.yaml
architecture: replication

tls:
  enabled: true
  autoGenerated: true

primary:
  storageClass: "piraeus-storage-replicated"

readReplicas:
  storageClass: "piraeus-storage-replicated"
###

helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgres --version 13.2.26 oci://registry-1.docker.io/bitnamicharts/postgresql -f /postgres/values.yaml -n postgres

#PV создаються автоматически на основе storageClass
#перепроверяем что PV для бд созданы корректно
kubectl get pv

#при необходимости обезопасить записи с бд от случайного удаления рекоменовано замени опции persistentVolumeReclaimPolicy: Delete на Retain
</pre>
