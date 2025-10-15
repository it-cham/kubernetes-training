# Lab: Sticky Sessions

A test is carried out with a sample application, that shows the behaviour of Kubernetes internal load balancing and default session un-awareness.

If this is a requirement, the network architecture (load balancers, reverse proxies) needs to be adjusted accordingly to forward the correct IP addresses. An ingress controller like NGINX can implement a workaround to make the sessions sticky, by adding a cookie, but the source IP still gets obfuscated.

## Setup

The attached manifests show a multi-replica Kubernetes deployment. The website shows the container and the client IP address (if configured correctly).

Url: [Ingress - Sticky Sessions](https://stickysession.k3s.test.local/StickySession/StickySessionServlet)

## Prerequisite - Private Docker Registry

If not running locally, the image needs to be built and shipped to a container registry, where Kubernetes can get the container from.

```shell
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout domain.key -out domain.crt \
    -subj "/CN=registry.test.local" \
    -addext "subjectAltName=DNS:localhost,DNS:registry.test.local,IP:10.0.0.2"
```

```shell
docker run -d \
  --restart=always \
  --name registry \
  -v "$(pwd)"/certs:/certs \
  -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  -p 443:443 \
  registry:3
```

Edit file `/etc/docker/daemon.json`
(Or on Docker Desktop: Preferences - Docker Engine)

```json
{
  "insecure-registries": ["registry.test.local"]
}
```

## Build Dockerfile

```shell
docker buildx build --platform linux/amd64 --provenance=false \
    -f Dockerfile \
    -t registry.test.local/stickysessions:0.1.1 .

docker push registry.test.local/stickysessions:0.1.1
```
