# Security Policy

## Reporting a vulnerability

Bu proje GitHub'da yayımlandığında, lütfen güvenlik açıklarını herkese açık bir tartışma yerine deponun **Security / Private vulnerability reporting** kanalından bildirin. Depo bunu desteklemiyorsa sorunu yeniden üretilebilir adımlarla bakım ekibine özel olarak iletin.

## Security design principles

- Uzaktan indirilen betik doğrudan çalıştırılabileceği için yayın erişimi korunmalı ve her sürüm incelenmelidir.
- CleanOS telemetri veya dışarıya otomatik raporlama yapmaz.
- Kayıt defteri ve servis değişiklikleri yerel işlem günlüğüne yazılır.
- Defender, Windows Update, ağ ve temel sistem servisleri toplu olarak devre dışı bırakılmaz.
- Appx kaldırmaları otomatik geri alınabilir olarak sunulmaz.
- Yönetici yetkisi yalnızca ihtiyaç duyulan işlemde kullanılmalıdır.
