# Future Steps
1. Backups: 
>[!info] Create:
```
pod=$(344kctl -n 344-group-project get pods -l app=vw-app -o jsonpath='{.items[0].metadata.name}') && \
344kctl $pod:/data vw-bak
```
>[!info] Restore
```
tar -C ./vw-bak -cpf - . | 344kctl exec -i deploy/vw-app -- tar -xpf - -C /data
```
Create a job that restores to pi with ssd attached, or nfs pvc