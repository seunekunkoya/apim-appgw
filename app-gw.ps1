$apimServiceName = "oleku"  
$resGroupName = "apim-appGw-RG" # resource group name
$location = "West US"           # Azure region

$gatewayHostname = "api.koyay.com"                 # API gateway host
$portalHostname = "dev.koyay.com"               # API developer portal host
$gatewayCertCerPath = "wildcard/api.cer" # full path to api.contoso.net .cer file
$gatewayCertPfxPath = "wildcard/api.pfx" # full path to api.contoso.net .pfx file
$portalCertPfxPath = "wildcard/portal.pfx"   # full path to portal.contoso.net .pfx file

$CertPfxPassword = "certificatePassword123"    # password for portal.contoso.net pfx certificate

$password = ConvertTo-SecureString -String $CertPfxPassword -Force -AsPlainText 

$apim = Get-AzApiManagement -ResourceGroupName $resGroupName -Name $apimServiceName

#Vnet Credentials
$vnet = Get-AzVirtualNetwork -Name "appgwvnet" -ResourceGroupName $resGroupName 


$appgatewaysubnetdata = $vnet.Subnets[0]
$apimsubnetdata = $vnet.Subnets[1]

#create APIM Vnet object using the subnet $apimsubnetdata
$apimVirtualNetwork = New-AzApiManagementVirtualNetwork -SubnetResourceId $apimsubnetdata.Id

$publicip = Get-AzPublicIpAddress -ResourceGroupName $resGroupName 

#create application gateway
$gipconfig = New-AzApplicationGatewayIPConfiguration -Name "gatewayIP01" -Subnet $appgatewaysubnetdata
#front end IP
$fp01 = New-AzApplicationGatewayFrontendPort -Name "port01"  -Port 443
#front end ip with public address
$fipconfig01 = New-AzApplicationGatewayFrontendIPConfig -Name "frontend1" -PublicIPAddress $publicip

$cert = New-AzApplicationGatewaySslCertificate -Name "cert01" -CertificateFile $gatewayCertPfxPath -Password $password
$certPortal = New-AzApplicationGatewaySslCertificate -Name "cert02" -CertificateFile $portalCertPfxPath -Password $password

#Create the HTTP listeners for the Application Gateway. Assign the front-end IP configuration, port, and TLS/SSL certificates to them.
$listener = New-AzApplicationGatewayHttpListener -Name "listener01" -Protocol "Https" -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $cert -HostName $gatewayHostname -RequireServerNameIndication true
$portalListener = New-AzApplicationGatewayHttpListener -Name "listener02" -Protocol "Https" -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $certPortal -HostName $portalHostname -RequireServerNameIndication true

#customprobes
$apimprobe = New-AzApplicationGatewayProbeConfig -Name "apimproxyprobe" -Protocol "Https" -HostName $gatewayHostname -Path "/status-0123456789abcdef" -Interval 30 -Timeout 120 -UnhealthyThreshold 8
$apimPortalProbe = New-AzApplicationGatewayProbeConfig -Name "apimportalprobe" -Protocol "Https" -HostName $portalHostname -Path "/internal-status-0123456789abcdef" -Interval 60 -Timeout 300 -UnhealthyThreshold 8

#upload certificate
$authcert = New-AzApplicationGatewayAuthenticationCertificate -Name "whitelistcert1" -CertificateFile $gatewayCertCerPath

#configure backend settings for d app gateway
$apimPoolSetting = New-AzApplicationGatewayBackendHttpSettings -Name "apimPoolSetting" -Port 443 -Protocol "Https" -CookieBasedAffinity "Disabled" -Probe $apimprobe -AuthenticationCertificates $authcert -RequestTimeout 180
$apimPoolPortalSetting = New-AzApplicationGatewayBackendHttpSettings -Name "apimPoolPortalSetting" -Port 443 -Protocol "Https" -CookieBasedAffinity "Disabled" -Probe $apimPortalProbe -AuthenticationCertificates $authcert -RequestTimeout 180

#backend IP address pool
$apimProxyBackendPool = New-AzApplicationGatewayBackendAddressPool -Name "apimbackend" -BackendIPAddresses $apim.PrivateIPAddresses[0]

#create application gateway rules
$rule01 = New-AzApplicationGatewayRequestRoutingRule -Name "rule1" -RuleType Basic -HttpListener $listener -BackendAddressPool $apimProxyBackendPool -BackendHttpSettings $apimPoolSetting
$rule02 = New-AzApplicationGatewayRequestRoutingRule -Name "rule2" -RuleType Basic -HttpListener $portalListener -BackendAddressPool $apimProxyBackendPool -BackendHttpSettings $apimPoolPortalSetting

#configure WAF
$sku = New-AzApplicationGatewaySku -Name "WAF_Medium" -Tier "WAF" -Capacity 2

#configure WAf in prevention mode
$config = New-AzApplicationGatewayWebApplicationFirewallConfiguration -Enabled $true -FirewallMode "Prevention"

#create application gateway
$appgwName = "apim-app-gw"
$appgw = New-AzApplicationGateway `
-Name $appgwName `
-ResourceGroupName $resGroupName `
-Location $location `
-BackendAddressPools $apimProxyBackendPool `
-BackendHttpSettingsCollection $apimPoolSetting, $apimPoolPortalSetting  `
-FrontendIpConfigurations $fipconfig01 `
-GatewayIpConfigurations $gipconfig `
-FrontendPorts $fp01 `
-HttpListeners $listener, $portalListener `
-RequestRoutingRules $rule01, $rule02 `
-Sku $sku `
-WebApplicationFirewallConfig $config `
-SslCertificates $cert, $certPortal `
-AuthenticationCertificates $authcert `
-Probes $apimprobe, $apimPortalProbe

#cname the APIM proxy hostname to appgw dns
Get-AzPublicIpAddress -ResourceGroupName $resGroupName -Name "publicIP01"



