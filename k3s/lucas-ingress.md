# Optional: expose Lucas's services with Traefik Ingress

The manifest currently mirrors the Docker Compose ports with `LoadBalancer`
Services:

| App | Service | Port |
| --- | --- | --- |
| Authentik | `authentik-server` | `9000` (HTTP), `9443` (HTTPS) |
| Pi-hole UI | `pihole-web` | `6789` |
| Website | `website` | `9876` |
| Pi-hole DNS | `pihole-dns` | `53` TCP and UDP |

k3s ships Traefik, and Traefik already owns host ports `80` and `443`. If you
want names instead of high ports, follow the steps below.

## 1. Change the HTTP Services to ClusterIP

In `k3s/deployments/lucas.yml`, change the `type:` of these Services from
`LoadBalancer` to `ClusterIP`:

- `authentik-server`
- `pihole-web`
- `website`

Leave `pihole-dns` as `LoadBalancer` (or `NodePort`); Ingress does not carry
DNS traffic.

## 2. Add the Ingress resources

Append these documents to `k3s/deployments/lucas.yml`:

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: authentik
  namespace: 344-group-project
spec:
  ingressClassName: traefik
  rules:
    - host: auth.344.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: authentik-server
                port:
                  number: 9000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pihole
  namespace: 344-group-project
spec:
  ingressClassName: traefik
  rules:
    - host: pihole.344.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: pihole-web
                port:
                  number: 6789
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: website
  namespace: 344-group-project
spec:
  ingressClassName: traefik
  rules:
    - host: www.344.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: website
                port:
                  number: 9876
```

The `number:` values are the Service ports, not the container ports.

## 3. Point names at Traefik

Get Traefik's external address:

```bash
kubectl get svc -n kube-system traefik
```

Use the `EXTERNAL-IP` (with k3s's ServiceLB this is usually a node IP), or any
node IP. Add entries to the hosts file on the machine you will browse from:

```text
192.168.1.165 auth.344.local pihole.344.local www.344.local
```

Then open:

- `http://auth.344.local/`
- `http://pihole.344.local/admin`
- `http://www.344.local/`

## 4. HTTPS (optional)

Traefik can terminate TLS. For a default/self-signed certificate, add a `tls`
section to an Ingress:

```yaml
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - auth.344.local
  rules:
    - host: auth.344.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: authentik-server
                port:
                  number: 9000
```

For a trusted certificate, install cert-manager or create a TLS Secret and
reference it with `secretName`. Keep the Ingress backend on port `9000` (HTTP);
Traefik handles TLS on port `443`. Do not point it at Authentik's `9443` unless
you specifically want Traefik to re-encrypt the connection.

## DNS note

`pihole-dns` is still exposed on port 53. If the nodes already run a resolver
on port 53 (commonly `systemd-resolved` on `127.0.0.53:53`), the k3s
LoadBalancer cannot bind that port. Check with:

```bash
sudo ss -lunpt | grep ':53 '
```

Options:

- Disable the systemd-resolved stub listener, or
- Change `pihole-dns` to `NodePort` and use `<node-ip>:<node-port>` as the DNS
  server. NodePort assigns a port from 30000-32767; set `nodePort: 30053` on
  both the TCP and UDP entries (the same node port is allowed for different
  protocols), then point clients at `<node-ip>:30053`.

Ingress does not solve DNS port conflicts.

## Rollback

Change the three Services back to `type: LoadBalancer` and remove the Ingress
documents, then re-apply:

```bash
kubectl apply -f k3s/deployments/lucas.yml
```
