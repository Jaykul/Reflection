#requires -version 2.0
function ConvertFrom-CliXml {
    param(
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]]$InputObject
    )
    begin
    {
        $OFS = "`n"
        [String]$xmlString = ""
    }
    process
    {
        $xmlString += $InputObject
    }
    end
    {
        $type = [PSObject].Assembly.GetType('System.Management.Automation.Deserializer')
        $ctor = $type.GetConstructor('instance,nonpublic', $null, @([xml.xmlreader]), $null)
        $sr = New-Object System.IO.StringReader $xmlString
        $xr = New-Object System.Xml.XmlTextReader $sr
        $deserializer = $ctor.Invoke($xr)
        $done = $type.GetMethod('Done', [System.Reflection.BindingFlags]'nonpublic,instance')
        while (!$type.InvokeMember("Done", "InvokeMethod,NonPublic,Instance", $null, $deserializer, @()))
        {
            try {
                $type.InvokeMember("Deserialize", "InvokeMethod,NonPublic,Instance", $null, $deserializer, @())
            } catch {
                Write-Warning "Could not deserialize ${string}: $_"
            }
        }
        $xr.Close()
        $sr.Dispose()
    }
}

function ConvertTo-CliXml {
    param(
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [PSObject[]]$InputObject
    )
    begin {
        $type = [PSObject].Assembly.GetType('System.Management.Automation.Serializer')
        $ctor = $type.GetConstructor('instance,nonpublic', $null, @([System.Xml.XmlWriter]), $null)
        $sw = New-Object System.IO.StringWriter
        $xw = New-Object System.Xml.XmlTextWriter $sw
        $serializer = $ctor.Invoke($xw)
        #$method = $type.GetMethod('Serialize', 'nonpublic,instance', $null, [type[]]@([object]), $null)
    }
    process {
        try {
            [void]$type.InvokeMember("Serialize", "InvokeMethod,NonPublic,Instance", $null, $serializer, [object[]]@($InputObject))
        } catch {
            Write-Warning "Could not serialize $($InputObject.GetType()): $_"
        }
    }
    end {    
        [void]$type.InvokeMember("Done", "InvokeMethod,NonPublic,Instance", $null, $serializer, @())
        $sw.ToString()
        $xw.Close()
        $sw.Dispose()
    }
}


$filesIn = ls | select * -first 2
$xml = $filesIn | ConvertTo-CliXml
$filesOut = $xml | ConvertFrom-CliXml

Compare-Object $filesIn $filesOut -IncludeEqual
# SIG # Begin signature block
# MIIXxAYJKoZIhvcNAQcCoIIXtTCCF7ECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMg5WFiO6reJZP/DMasSS8OHt
# 7KigghL3MIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
# AQUFADCBizELMAkGA1UEBhMCWkExFTATBgNVBAgTDFdlc3Rlcm4gQ2FwZTEUMBIG
# A1UEBxMLRHVyYmFudmlsbGUxDzANBgNVBAoTBlRoYXd0ZTEdMBsGA1UECxMUVGhh
# d3RlIENlcnRpZmljYXRpb24xHzAdBgNVBAMTFlRoYXd0ZSBUaW1lc3RhbXBpbmcg
# Q0EwHhcNMTIxMjIxMDAwMDAwWhcNMjAxMjMwMjM1OTU5WjBeMQswCQYDVQQGEwJV
# UzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFu
# dGVjIFRpbWUgU3RhbXBpbmcgU2VydmljZXMgQ0EgLSBHMjCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBALGss0lUS5ccEgrYJXmRIlcqb9y4JsRDc2vCvy5Q
# WvsUwnaOQwElQ7Sh4kX06Ld7w3TMIte0lAAC903tv7S3RCRrzV9FO9FEzkMScxeC
# i2m0K8uZHqxyGyZNcR+xMd37UWECU6aq9UksBXhFpS+JzueZ5/6M4lc/PcaS3Er4
# ezPkeQr78HWIQZz/xQNRmarXbJ+TaYdlKYOFwmAUxMjJOxTawIHwHw103pIiq8r3
# +3R8J+b3Sht/p8OeLa6K6qbmqicWfWH3mHERvOJQoUvlXfrlDqcsn6plINPYlujI
# fKVOSET/GeJEB5IL12iEgF1qeGRFzWBGflTBE3zFefHJwXECAwEAAaOB+jCB9zAd
# BgNVHQ4EFgQUX5r1blzMzHSa1N197z/b7EyALt0wMgYIKwYBBQUHAQEEJjAkMCIG
# CCsGAQUFBzABhhZodHRwOi8vb2NzcC50aGF3dGUuY29tMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwPwYDVR0fBDgwNjA0oDKgMIYuaHR0cDovL2NybC50aGF3dGUuY29tL1Ro
# YXd0ZVRpbWVzdGFtcGluZ0NBLmNybDATBgNVHSUEDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCAQYwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0y
# MDQ4LTEwDQYJKoZIhvcNAQEFBQADgYEAAwmbj3nvf1kwqu9otfrjCR27T4IGXTdf
# plKfFo3qHJIJRG71betYfDDo+WmNI3MLEm9Hqa45EfgqsZuwGsOO61mWAK3ODE2y
# 0DGmCFwqevzieh1XTKhlGOl5QGIllm7HxzdqgyEIjkHq3dlXPx13SYcqFgZepjhq
# IhKjURmDfrYwggSjMIIDi6ADAgECAhAOz/Q4yP6/NW4E2GqYGxpQMA0GCSqGSIb3
# DQEBBQUAMF4xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEwMC4GA1UEAxMnU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNlcyBD
# QSAtIEcyMB4XDTEyMTAxODAwMDAwMFoXDTIwMTIyOTIzNTk1OVowYjELMAkGA1UE
# BhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTQwMgYDVQQDEytT
# eW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIFNpZ25lciAtIEc0MIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAomMLOUS4uyOnREm7Dv+h8GEKU5Ow
# mNutLA9KxW7/hjxTVQ8VzgQ/K/2plpbZvmF5C1vJTIZ25eBDSyKV7sIrQ8Gf2Gi0
# jkBP7oU4uRHFI/JkWPAVMm9OV6GuiKQC1yoezUvh3WPVF4kyW7BemVqonShQDhfu
# ltthO0VRHc8SVguSR/yrrvZmPUescHLnkudfzRC5xINklBm9JYDh6NIipdC6Anqh
# d5NbZcPuF3S8QYYq3AhMjJKMkS2ed0QfaNaodHfbDlsyi1aLM73ZY8hJnTrFxeoz
# C9Lxoxv0i77Zs1eLO94Ep3oisiSuLsdwxb5OgyYI+wu9qU+ZCOEQKHKqzQIDAQAB
# o4IBVzCCAVMwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwcwYIKwYBBQUHAQEEZzBlMCoGCCsGAQUFBzABhh5odHRw
# Oi8vdHMtb2NzcC53cy5zeW1hbnRlYy5jb20wNwYIKwYBBQUHMAKGK2h0dHA6Ly90
# cy1haWEud3Muc3ltYW50ZWMuY29tL3Rzcy1jYS1nMi5jZXIwPAYDVR0fBDUwMzAx
# oC+gLYYraHR0cDovL3RzLWNybC53cy5zeW1hbnRlYy5jb20vdHNzLWNhLWcyLmNy
# bDAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMjAdBgNV
# HQ4EFgQURsZpow5KFB7VTNpSYxc/Xja8DeYwHwYDVR0jBBgwFoAUX5r1blzMzHSa
# 1N197z/b7EyALt0wDQYJKoZIhvcNAQEFBQADggEBAHg7tJEqAEzwj2IwN3ijhCcH
# bxiy3iXcoNSUA6qGTiWfmkADHN3O43nLIWgG2rYytG2/9CwmYzPkSWRtDebDZw73
# BaQ1bHyJFsbpst+y6d0gxnEPzZV03LZc3r03H0N45ni1zSgEIKOq8UvEiCmRDoDR
# EfzdXHZuT14ORUZBbg2w6jiasTraCXEQ/Bx5tIB7rGn0/Zy2DBYr8X9bCT2bW+IW
# yhOBbQAuOA2oKY8s4bL0WqkBrxWcLC9JG9siu8P+eJRRw4axgohd8D20UaF5Mysu
# e7ncIAkTcetqGVvP6KUwVyyJST+5z3/Jvz4iaGNTmr1pdKzFHTx/kuDDvBzYBHUw
# ggUmMIIEDqADAgECAhACXbrxBhFj1/jVxh2rtd9BMA0GCSqGSIb3DQEBCwUAMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0EwHhcNMTUwNTA0MDAwMDAwWhcNMTYwNTExMTIwMDAw
# WjBtMQswCQYDVQQGEwJVUzERMA8GA1UECBMITmV3IFlvcmsxFzAVBgNVBAcTDldl
# c3QgSGVucmlldHRhMRgwFgYDVQQKEw9Kb2VsIEguIEJlbm5ldHQxGDAWBgNVBAMT
# D0pvZWwgSC4gQmVubmV0dDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
# AJfRKhfiDjMovUELYgagznWf+HFcDENk118Y/K6UkQDwKmVyVOvDyaVefjSmZZcV
# NZqqYpm9d/Iajf2dauyC3pg3oay8KfXAADLHgbmbvYDc5zGuUNsTzMUOKlp9h13c
# qsg898JwpRpI659xCQgJjZ6V83QJh+wnHvjA9ojjA4xkbwhGp4Eit6B/uGthEA11
# IHcFcXeNI3fIkbwWiAw7ZoFtSLm688NFhxwm+JH3Xwj0HxuezsmU0Yc/po31CoST
# nGPVN8wppHYZ0GfPwuNK4TwaI0FEXxwdwB+mEduxa5e4zB8DyUZByFW338XkGfc1
# qcJJ+WTyNKFN7saevhwp02cCAwEAAaOCAbswggG3MB8GA1UdIwQYMBaAFFrEuXsq
# CqOl6nEDwGD5LfZldQ5YMB0GA1UdDgQWBBQV0aryV1RTeVOG+wlr2Z2bOVFAbTAO
# BgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwdwYDVR0fBHAwbjA1
# oDOgMYYvaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1jcy1n
# MS5jcmwwNaAzoDGGL2h0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3Vy
# ZWQtY3MtZzEuY3JsMEIGA1UdIAQ7MDkwNwYJYIZIAYb9bAMBMCowKAYIKwYBBQUH
# AgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwgYQGCCsGAQUFBwEBBHgw
# djAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tME4GCCsGAQUF
# BzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRTSEEyQXNz
# dXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0B
# AQsFAAOCAQEAIi5p+6eRu6bMOSwJt9HSBkGbaPZlqKkMd4e6AyKIqCRabyjLISwd
# i32p8AT7r2oOubFy+R1LmbBMaPXORLLO9N88qxmJfwFSd+ZzfALevANdbGNp9+6A
# khe3PiR0+eL8ZM5gPJv26OvpYaRebJTfU++T1sS5dYaPAztMNsDzY3krc92O27AS
# WjTjWeILSryqRHXyj8KQbYyWpnG2gWRibjXi5ofL+BHyJQRET5pZbERvl2l9Bo4Z
# st8CM9EQDrdG2vhELNiA6jwenxNPOa6tPkgf8cH8qpGRBVr9yuTMSHS1p9Rc+ybx
# FSKiZkOw8iCR6ZQIeKkSVdwFf8V+HHPrETCCBTAwggQYoAMCAQICEAQJGBtf1btm
# dVNDtW+VUAgwDQYJKoZIhvcNAQELBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoT
# DERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UE
# AxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTEzMTAyMjEyMDAwMFoX
# DTI4MTAyMjEyMDAwMFowcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0
# IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNl
# cnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBDQTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAPjTsxx/DhGvZ3cH0wsxSRnP0PtFmbE620T1f+Wo
# ndsy13Hqdp0FLreP+pJDwKX5idQ3Gde2qvCchqXYJawOeSg6funRZ9PG+yknx9N7
# I5TkkSOWkHeC+aGEI2YSVDNQdLEoJrskacLCUvIUZ4qJRdQtoaPpiCwgla4cSocI
# 3wz14k1gGL6qxLKucDFmM3E+rHCiq85/6XzLkqHlOzEcz+ryCuRXu0q16XTmK/5s
# y350OTYNkO/ktU6kqepqCquE86xnTrXE94zRICUj6whkPlKWwfIPEvTFjg/Bougs
# UfdzvL2FsWKDc0GCB+Q4i2pzINAPZHM8np+mM6n9Gd8lk9ECAwEAAaOCAc0wggHJ
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoG
# CCsGAQUFBwMDMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8EejB4
# MDqgOKA2hjRodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVk
# SURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGln
# aUNlcnRBc3N1cmVkSURSb290Q0EuY3JsME8GA1UdIARIMEYwOAYKYIZIAYb9bAAC
# BDAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAoG
# CGCGSAGG/WwDMB0GA1UdDgQWBBRaxLl7KgqjpepxA8Bg+S32ZXUOWDAfBgNVHSME
# GDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzANBgkqhkiG9w0BAQsFAAOCAQEAPuwN
# WiSz8yLRFcgsfCUpdqgdXRwtOhrE7zBh134LYP3DPQ/Er4v97yrfIFU3sOH20ZJ1
# D1G0bqWOWuJeJIFOEKTuP3GOYw4TS63XX0R58zYUBor3nEZOXP+QsRsHDpEV+7qv
# tVHCjSSuJMbHJyqhKSgaOnEoAjwukaPAJRHinBRHoXpoaK+bp1wgXNlxsQyPu6j4
# xRJon89Ay0BEpRPw5mQMJQhCMrI2iiQC/i9yfhzXSUWW6Fkd6fp0ZGuy62ZD2rOw
# jNXpDd32ASDOmTFjPQgaGLOBm0/GkxAG/AeB+ova+YJJ92JuoVP6EpQYhS6Skepo
# bEQysmah5xikmmRR7zGCBDcwggQzAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYD
# VQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAv
# BgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EC
# EAJduvEGEWPX+NXGHau130EwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAI
# oAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIB
# CzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFLDeF7iCNInPgeAmgEeF
# XREG+IdOMA0GCSqGSIb3DQEBAQUABIIBAE5APgDlgL83ZHJXFvxhAA/4SAVfLDEI
# 9NQ07fuuMqsIWajG/HtOihyTzAXqmaIPYWSoTtADFn3jjDf8Lna09/ogA9x6B3wG
# xdTWwEn7tkU9lVvsTw53jIb2xgZN+PgS2Ti3PE76KiTaKd0hvSprqpQC1SE+3vD0
# 3L1dtnNCmYRVRFw27/+UiDnOoiPKnV90QQjqB2CNiodFIWRYwh2YSr4cFNhDmrtQ
# RJ1Uc6/1SKt8qr8wPtBv+WOBtGYbqHUqUJwouIohRiBIOA9M9ANf0AgUt3bUy9lT
# 9nW2DY4AL8P4hKa9E9p1YyqfQyXAgYyPJV3h4GDBhl/556PPq8dt3nShggILMIIC
# BwYJKoZIhvcNAQkGMYIB+DCCAfQCAQEwcjBeMQswCQYDVQQGEwJVUzEdMBsGA1UE
# ChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUg
# U3RhbXBpbmcgU2VydmljZXMgQ0EgLSBHMgIQDs/0OMj+vzVuBNhqmBsaUDAJBgUr
# DgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMTUwNTA1MDU1ODQ0WjAjBgkqhkiG9w0BCQQxFgQU1pnbVEEVtu+xZy9jxHyN
# Y2jx70wwDQYJKoZIhvcNAQEBBQAEggEAiyrkIBhFyYk4lLyrNLC+NuvZcpcBKZya
# M0opkU03Y+kYikJjHRvZfDuykRaPO3jVfRivM+K+uxRFmhXgHvuhM79ZwYs8uCYd
# zbge7rUzO82+xjzmLSAdDEX7xtL6yIyfWNdudnXLA0JSBJYXrEZPkeq6brbwqj4K
# Z1xhHCYgdnxfq7rKqCMwkNNUSsiLn/08pvsvATH1BhFCfLW2BjK3/cDI95Kukusd
# hOvk9Gi6E9Azw1hGC6vtjWleXLStwlyf9PocJTZbiiwaAvr7iFaAW/l9202vjcFH
# 6bvpur4S7U3V8w2Jq17gBVSHMU6Mhkx7/143kjBz/GgcAfUgT5auQA==
# SIG # End signature block
