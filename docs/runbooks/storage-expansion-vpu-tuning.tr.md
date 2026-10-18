# İşletim Rehberi: Canlı Depolama Genişletme ve Disk Performans Ayarları

**Diller:** [English](storage-expansion-vpu-tuning.md) | [Türkçe](storage-expansion-vpu-tuning.tr.md)

## 1. Genel Bakış

50 GB boyutundaki açılış diskimde yer azalmaya başladığında, sanal makineyi kapatmadan ve çalışan konteynerleri durdurmadan diski 100 GB boyutuna çıkarmam gerekti. Oracle Cloud (OCI) üzerinde blok ve açılış diskleri sunucu çalışmaya devam ederken çevrim içi olarak büyütülebilir.

Bu rehber, çalışan ext4 kök bölümünü `growpart` ve `resize2fs` ile canlı olarak nasıl genişlettiğimi ve disk IOPS ile yazma hızını artırmak için OCI Volume Performance Unit (VPU) ayarını nasıl yükselttiğimi kayıt altına alır.

## 2. Canlı Genişletme Adımları

### Adım 1: OCI Konsolunda Disk Boyutunu Büyütme
1. OCI Web Konsolunu açın.
2. **Storage** > **Block Volumes** veya **Boot Volumes** bölümüne gidin.
3. Bağlı açılış diskine tıklayın ve **Edit** seçeneğini seçin.
4. Yeni boyutu (örneğin 50 GB yerine 100 GB) girip değişiklikleri kaydedin. Hipervizör Linux çekirdeğine anında bir SCSI kapasite güncelleme sinyali gönderir.

### Adım 2: Sunucu İçinde Bölüm ve Dosya Sistemini Genişletme

Disk bölüm numaralarını elle aramamak için genişletme komutlarını bir yardımcı betik (`scripts/setup-storage.sh`) içine topladım:

```bash
sudo ./scripts/setup-storage.sh
```

Komutları doğrudan çalıştırmak isterseniz:

```bash
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
df -h /
```

Her komutun görevi:
- `growpart /dev/sda 1`: Bellekteki GPT bölüm tablosunu güncelleyerek 1 numaralı bölümün `/dev/sda` üzerindeki yeni ayrılan sektörleri kapsamasını sağlar.
- `resize2fs /dev/sda1`: ext4 sürücüsüne yeni blokları kullanmasını bildirir. ext4 canlı boyutlandırmayı desteklediği için kök dosya sistemi bağlı kalmaya devam ederken işlem birkaç saniye içinde tamamlanır.

## 3. OCI Volume Performance Units (VPU)

OCI blok depolama performansı hem disk boyutuyla hem de seçilen VPU katmanıyla ölçeklenir:
- Düşük Maliyet (GB başına 0 VPU): Soğuk depolama ve yedekler için temel hız
- Dengeli (GB başına 10 VPU): Standart açılış ve konteyner diskleri için varsayılan OCI katmanı
- Yüksek Performans (GB başına 20 VPU): Yoğun disk yazma işlemleri için daha yüksek IOPS tavanı
- Ultra Yüksek Performans (GB başına 30 ile 120 VPU): En yüksek IOPS ve bant genişliği tavanı

Diski 100 GB boyutuna çıkarırken, yoğun dünya kayıtları (autosave) ve konteyner imajı açma işlemleri sırasında yazma gecikmelerini düşürmek için OCI Konsolundan disk performansını 30 VPU seviyesine çektim. VPU değişiklikleri diski ayırmaya gerek kalmadan saniyeler içinde devreye girer.
