After running the ansible playbook run-deployments, you will have to add the certmanager certificate to your trusted certificates by using the following command.

kubectl --kubeconfig ./k3s/k3s_config -n cert-manager get secret root-secret \
  -o jsonpath='{.data.tls\.crt}' | base64 -D > ./root-ca.crt

344 Project

Networking Services | K3s
https://docs.k3s.io/networking/networking-services

Persistent Volumes | Kubernetes
https://kubernetes.io/docs/concepts/storage/persistent-volumes/

local-path-provisioner/examples/pod-with-local-volume/pod.yaml at master · rancher/local-path-provisioner
https://github.com/rancher/local-path-provisioner/blob/master/examples/pod-with-local-volume/pod.yaml

Deploy Vaultwarden on Thalassa Cloud Kubernetes – Thalassa Cloud
https://docs.thalassa.cloud/docs/kubernetes/guides/apps/deploy-vaultwarden/

dani-garcia/vaultwarden: Unofficial Bitwarden compatible server written in Rust, formerly known as bitwarden_rs
https://github.com/dani-garcia/vaultwarden

vaultwarden/.env.template at main · dani-garcia/vaultwarden
https://github.com/dani-garcia/vaultwarden/blob/main/.env.template

Service | Kubernetes
https://kubernetes.io/docs/concepts/services-networking/service/

Ingress | Kubernetes
https://kubernetes.io/docs/concepts/services-networking/ingress/

kubectl apply - cert-manager Documentation
https://cert-manager.io/docs/installation/kubectl/

Annotated Ingress resource - cert-manager Documentation
https://cert-manager.io/docs/usage/ingress/

SelfSigned - cert-manager Documentation
https://cert-manager.io/docs/configuration/selfsigned/

SelfSigned - cert-manager Documentation
https://cert-manager.io/docs/configuration/selfsigned/#bootstrapping-ca-issuers

