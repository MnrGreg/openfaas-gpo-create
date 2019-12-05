### Create Funtion template scaffolding
```
faas-cli template pull https://github.com/openfaas-incubator/powershell-http-template
faas-cli new faas-gpoacl-create --lang powershell-http --gateway https://openfaas.services.west.nonprod.contoso.com
```

### Authenticate to OpenFaaS control plane
```
faas-cli login -g https://openfaas.services.west.nonprod.contoso.com/ -u admin --password-stdin
faas-cli version
faas-cli list -g https://openfaas.services.west.nonprod.contoso.com/
```

### Build and deploy function
```
htpasswd -c auth faas-gpoacl-create-token
kubectl create secret generic -n openfaas --from-file=auth faas-gpoacl-create-basic-auth
kubectl create -n openfaas -f ingress.yaml
kubectl create -n openfaas-fn -f secret.yaml
faas-cli build -f ./faas-gpoacl-create.yml
faas-cli push -f ./faas-gpoacl-create.yml 
faas-cli deploy -f ./faas-gpoacl-create.yml
```

### Trigger Function
```json
curl -u 'faas-gpoacl-create-token:XXXXXXX' -s https://openfaas.services.west.nonprod.contoso.com/function/faas-gpoacl-create \
    -d '{
    "businessUnit": "TDS",
    "application": "SANDBOX",
    "environment": "nonprod",
    "domain": "contoso.com",
    "group": "lsa_linux_ops"
    }'
```
