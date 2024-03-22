#!/bin/bash
apt-get -y install selinux-utils

setenforce 0
sudo ufw disable
sudo ufw status

echo "SELINUX=disabled" > /etc/selinux/config

swapoff -a
sed -i '/swap/ s/^\(.*\)$/#\1/g' /etc/fstab

# /etc/hosts 127.0.0.1 master
echo 'master' > /etc/hostname

curl -fsSL https://test.docker.com -o test-docker.sh
sudo sh test-docker.sh
sudo gpasswd -a $USER docker
newgrp docker


mkdir /etc/docker
cat > /etc/docker/daemon.json << EOF
{
    "registry-mirrors": ["http://hub-mirror.c.163.com","https://9xx4btvq.mirror.aliyuncs.com"],
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
    		"max-size": "100m"
		}
}
EOF
systemctl daemon-reload && systemctl enable docker && systemctl restart docker

# x86-64架构
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# x86-64架构
curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client --output=yaml

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 设置所需的 sysctl 参数，参数在重新启动后保持不变
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# 应用 sysctl 参数而不重新启动
sudo sysctl --system

lsmod | grep br_netfilter
lsmod | grep overlay

sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward


sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

sudo apt update
sudo apt install -y containerd.io
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system


sudo apt-get install -y apt-transport-https ca-certificates curl
# sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg
sudo cp /etc/apt/keyrings/kubernetes-archive-keyring.gpg  /usr/share/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
# 换源
# echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
# sudo apt-get update


sudo rm /etc/containerd/config.toml
containerd config default > /etc/containerd/config.toml 
sed -i 's/registry.k8s.io\/pause:3.6/registry.aliyuncs.com\/google_containers\/pause:3.9/g' /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl daemon-reload 
systemctl restart containerd.service 
systemctl restart kubelet


kubeadm reset all -f
ipvsadm --clear
rm -fr ~/.kube/  /etc/kubernetes/* var/lib/etcd/* /etc/cni/net.d
systemctl restart kubelet && systemctl status kubelet

kubeadm init \
--apiserver-advertise-address=192.168.1.175 \
--apiserver-bind-port=6443 \
--pod-network-cidr=10.244.0.0/16 \
--service-cidr=172.96.0.0/12 \
--image-repository registry.aliyuncs.com/google_containers  \
--ignore-preflight-errors=Swap \
--upload-certs \
--v=6


mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "admin,smd013012,1" > /etc/kubernetes/pki/basic_auth_file
sed -i 's/- --allow-privileged=true/- --allow-privileged=true\n    - --service-node-port-range=1-50000/g' /etc/kubernetes/manifests/kube-apiserver.yaml   
systemctl restart kubelet


kubectl describe nodes master  | grep Taints

kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl taint nodes --all node.kubernetes.io/not-ready-


# # 使用calico 当前最新
# curl https://docs.projectcalico.org/manifests/calico.yaml -o calico.yaml
# kubectl apply -f calico.yaml

# 使用flannel 当前最新
# curl https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml -o flannel.yml
kubectl apply -f flannel.yml

kubectl create ns kubernetes-dashboard

mkdir /root/key && cd /root/key
openssl genrsa -out dashboard.key 2048 
openssl req -new -out dashboard.csr -key dashboard.key -subj '/CN=192.168.1.31'
openssl x509 -req -in dashboard.csr -signkey dashboard.key -out dashboard.crt
kubectl delete secret kubernetes-dashboard-certs -n kubernetes-dashboard
kubectl create secret generic kubernetes-dashboard-certs --from-file=dashboard.key --from-file=dashboard.crt -n kubernetes-dashboard


kubectl create clusterrolebinding test:anonymous --clusterrole=cluster-admin --user=system:anonymous
kubectl create clusterrolebinding login-on-dashboard-with-cluster-admin --clusterrole=cluster-admin --user=admin


kubectl apply -f dashboard.yml
kubectl apply -f dashboard-admin.yml