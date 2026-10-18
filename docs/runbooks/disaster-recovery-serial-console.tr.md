# İşletim Rehberi: Bant Dışı Seri Konsol Kurtarma

**Diller:** [English](disaster-recovery-serial-console.md) | [Türkçe](disaster-recovery-serial-console.tr.md)

## 1. Arka Plan ve Kilitlenme Analizi

OCI sunucumda yerel güvenlik duvarı kurallarıyla denemeler yaparken yanlışlıkla kendi SSH erişimimi kestim. Bulut imajları standart masaüstü Linux kurulumlarından farklı çalıştığı için sunucuyu silmeden kurtarmak derin bir önyükleyici (bootloader) müdahalesi gerektirdi.

Bu kilitlenme can sıkıcı bir bulut açmazından kaynaklandı:
- Yazdığım iptables kuralları gelen TCP port 22 paketlerini düşürdüğü için SSH bağlantım zaman aşımına uğradı.
- OCI Seri Konsoluna bağlandığımda karşıma standart bir kullanıcı giriş ekranı (`ubuntu login:`) geldi. Ancak Ubuntu bulut imajları SSH anahtarı kullanımını zorunlu kılmak için yerel kullanıcı parolası olmadan kurulur. Denediğim parolalar reddedildi.
- OCI Run Command özelliği sunucuyu kurtaramadı çünkü arka plandaki `oracle-cloud-agent` servisi OCI ile yerel meta veri IP'si `169.254.169.254` üzerinden haberleşir. Güvenlik duvarım bu adresi de engellediği için gönderdiğim komutlar bulutta `ACCEPTED` durumunda asılı kaldı ve sunucuya ulaşamadı.
- Bulut ağı tarafında ise alt ağ yönlendirme tablosunda `0.0.0.0/0` trafiğini bir İnternet Ağ Geçidine yönlendiren kural eksikse dış trafik sunucuya ulaşıp dönemez.

Bu rehber sunucuyu silmeden veya kaynak tahsisini kaybetmeden sistemi GRUB önyükleyicisi üzerinden nasıl kurtardığımı anlatır.

## 2. Kurtarma Adımları

### Adım 1: OCI Cloud Shell Seri Bağlantısını Açma

1. OCI Web Konsolunda **Compute** > **Instances** bölümüne gidin ve sunucunuzu seçin.
2. Sol alt menüde **Resources** altındaki **Console connection** seçeneğine tıklayın.
3. **Launch Cloud Shell connection** düğmesine basın.
4. Açılan Cloud Shell terminal penceresini tarayıcınızda sunucu sayfasıyla yan yana görünür tutun.

### Adım 2: Önyükleme Sırasını Durdurma

1. Sunucu detay sayfasında **Reboot** düğmesine tıklayın. İşletim sistemi standart kapatma sinyaline yanıt vermiyorsa **Force Reboot** seçeneğini kullanın.
2. Hemen Cloud Shell terminal penceresine tıklayın.
3. Sunucu açılırken klavyeden aralıksız **Esc** tuşuna basın.
4. UEFI Boot Manager ekranı gelirse ana Ubuntu diskini seçip **Enter** tuşuna basın, ardından GRUB geri sayımını durdurmak için hemen **Aşağı Ok** veya **Esc** tuşuna basın.

### Adım 3: GRUB Üzerinden Kök Kabuğunu Başlatma

`grub>` komut istemine ulaştığınızda aşağıdaki komutları sırasıyla girin:

```text
set root=(hd0,gpt1)
linux /boot/vmlinuz root=/dev/sda1 rw init=/bin/bash
initrd /boot/initrd.img
boot
```

`/boot/vmlinuz` bulunamazsa `/boot` önekini kaldırarak `/vmlinuz` ve `/initrd.img` yollarını deneyin.

Bu önyükleme parametrelerinin sistemdeki görevi:
- `set root=(hd0,gpt1)`: GRUB işaretçisini Ubuntu dosya sisteminin bulunduğu birincil diskin 1 numaralı bölümüne yönlendirir.
- `linux /boot/vmlinuz root=/dev/sda1`: Çekirdek ikilisini belleğe yükler ve kök dosya sisteminin hangi blok aygıtında olduğunu bildirir.
- `rw`: Kök dosya sistemini en baştan okuma ve yazma yetkisiyle bağlar. Bu parametre verilmezse disk salt okunur açılır ve diski elle yeniden bağlamadan parola değiştirmeyi veya dosya kaydetmeyi engeller.
- `init=/bin/bash`: Çekirdeğe standart başlatma yöneticisi (systemd) yerine PID 1 olarak doğrudan etkileşimli bash kabuğu açmasını söyler. Bu sayede kullanıcı doğrulaması, systemd servisleri ve parola sorma ekranları tamamen atlanır.
- `initrd /boot/initrd.img`: Sanal kök diski okumak için gereken SCSI depolama sürücülerini içeren başlangıç RAM diskini yükler.
- `boot`: Verilen parametrelerle çekirdeği çalıştırır ve doğrudan root kabuğunu açar.

### Adım 4: Kök Kabuğunda Kilitlenmeyi Çözme

Sistem birkaç saniye içinde doğrudan şifresiz bir root kabuğunda açılacaktır (`root@...:/#`). Aşağıdaki komutları sırayla çalıştırın:

```bash
passwd ubuntu
iptables -F
iptables-save > /etc/iptables/rules.v4
reboot -f
```

Bu adımların neden zorunlu olduğu:
- `passwd ubuntu`: Bulut imajları SSH anahtarlarına dayandığı için yerel parola taşımaz. Burada belirlenen parola, ileride seri konsol gerektiğinde GRUB aşamasına girmeden normal giriş yapabilmeyi sağlar. `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf` içinde `PasswordAuthentication no` ayarı aktif kaldığı için bu parola internet üzerinden SSH ile girişe izin vermez ve güvenliği düşürmez.
- `iptables -F`: Port 22 trafiğini kesen veya yerel meta veri IP'si `169.254.169.254` ile iletişimi engelleyen bellekteki tüm aktif kuralları temizler.
- `iptables-save > /etc/iptables/rules.v4`: Tek kullanıcı modunda başlangıç servisleri çalışmadığı için diskteki `/etc/iptables/rules.v4` dosyasında duran eski kurallar belleğe henüz yüklenmemiştir. Sadece `iptables -F` çalıştırmak belleği temizler ama diskteki dosya değişmez. Boş kural tablosunu bu dosyanın üzerine yazmak, normal açılışta `netfilter-persistent` servisinin eski kuralları tekrar yüklemesini önler.
- `reboot -f`: systemd çalışmadığı için normal `systemctl reboot` veya `shutdown` komutları hata verir. `-f` bayrağı çekirdeğin sunucuyu doğrudan donanımsal olarak yeniden başlatmasını sağlar.

### Adım 5: OCI VCN Ağ Yönlendirmelerini ve Güvenlik Listelerini Doğrulama

Sunucu yeniden başladıktan sonra SSH bağlantısı hala zaman aşımına uğruyorsa, sorun sunucu içinde değil OCI bulut ağ katmanındadır:

1. OCI Konsolunda **Networking** > **Virtual Cloud Networks** sayfasına gidin ve ilgili VCN seçin.
2. **Resources** altından bir **Internet Gateway** kaynağının var olduğunu ve Available durumda olduğunu kontrol edin.
3. **Route Tables** sekmesini açın ve alt ağa bağlı yönlendirme tablosunu seçin.
4. `0.0.0.0/0` trafiğini İnternet Ağ Geçidine yönlendiren bir kural bulunduğundan emin olun. Bu kural olmadan sunucudan çıkan yanıt paketleri internete geri dönemez.
5. Alt ağa bağlı **Security List** (veya sunucuya bağlı **Network Security Group**) ayarlarını kontrol edin.
6. Kaynak CIDR `0.0.0.0/0`, protokol `TCP` ve hedef port `22` olan bir Ingress Rule bulunduğunu doğrulayın. Bu kural olmadan OCI sanal ağ hipervizörü gelen paketleri sanal ağ kartına ulaşmadan düşürür.
