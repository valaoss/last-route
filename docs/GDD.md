# LAST ROUTE — Game Design & Production Document (v1)

> Kaynak: onaylanan geliştirme planı. Uygulama durumu için bkz. `docs/STATUS.md`.

## 0. Context
Days Gone'dan *ilke düzeyinde* ilham alan, özgün bir mobil açık dünya zombi survival oyunu. Mevcut proje yok. Kullanıcı motor/editörle minimum uğraşmak, geliştirmeyi bana devretmek istiyor; görsel sonuç tatmin edici olmalı. İlk teslimat: bu planın `docs/` altına tam GDD olarak yazılması + **P0 prototip** (motosiklet hissi + combat hissi, iki test sahnesi).

Bu dosya hem tasarım kararlarını hem uygulama sırasını içerir. `docs/` altındaki GDD bu planın genişletilmiş hâli olacak.

---

## 1. Motor ve üretim kararı

### Karar: Godot 4.6+ (Mobile renderer), GDScript, veri odaklı `.tres` kaynakları
| Kriter | Godot | Unity 6 URP |
|---|---|---|
| Benim editörsüz üretebilmem | Sahne/kaynak/kod düz metin → %100 | Prefab/sahne YAML'ı GUID bağımlı → pratikte editör gerekir |
| Kullanıcı yükü | Portable tek exe, F5 | Hub + lisans + paket yöneticisi + editör kurulumu |
| Doğrulama | `--headless` ile script/sahne yükleme, test, ekran görüntüsü alabilirim | Batchmode var ama lisans/derleme süresi ağır |
| Görsel tavan | Lightmap GI, fog, glow, AgX tonemap, özel shader → stilize gerçekçilik için yeterli | Daha yüksek, ama fark asset/sanatçıdan gelir |
| Mobil | Mobile renderer + Android export (tek seferlik SDK kurulumu) | Daha olgun |

Unity'nin görsel avantajı motorun kendisinden değil, Asset Store ve editörde elle yapılan sanat işinden gelir; kullanıcı bunu yapmak istemediği için avantaj kullanılamaz. **Godot ile ben uçtan uca üretirim.**

### Varlık stratejisi (kullanıcı hiçbir şey indirmez — `scripts/fetch_assets.ps1` ile ben indiririm)
- **Karakter + animasyon:** Quaternius *Universal Animation Library* (CC0, humanoid, locomotion/silah/melee/dodge/hit-react) + Quaternius CC0 karakter/zombi modelleri. Godot import'ta `SkeletonProfileHumanoid` ile retarget → tüm karakterler aynı animasyon setini paylaşır.
- **Şehir:** Kenney City/Road kitleri (CC0) taban; **tek ortak materyal sistemi** ile yeniden giydirilir (bkz. Art Bible §6).
- **Motosiklet:** CC0/CC-BY low-poly model (Poly Pizza); bulunamazsa parçalı (gövde, depo, çatal, teker, gidon, çanta) olarak ben modellerim — zaten upgrade'lerin görsel parça olarak takılması için parçalı yapı gerekiyor.
- **Ses:** Motor sesi **prosedürel sentez** (`AudioStreamGenerator`, RPM'e bağlı harmonik + gürültü katmanları) — asset gerektirmez ve fiziğe birebir bağlı. Silah/ortam: CC0 (Kenney, freesound CC0 filtresi), katmanlı.
- Tüm lisanslar `assets/LICENSES.md`'de.

**Dürüst risk:** CC0 paketler low-poly'dir. "Ucuz" görünmemesi; materyal birliği, ışık, sis, renk derecelendirmesi ve kompozisyonla sağlanacak. P0 sonunda ekran görüntüsüyle kullanıcı onayı alınır; tatmin etmezse sanat yönü revize edilir (motor değiştirmeden).

### Repo yapısı — `C:\Users\USER\Desktop\last-route`
`project.godot` kökte olmak zorunda (Godot `res://` kökü). Klasörler kullanıcı kurallarına uygun:
```
project.godot
docs/        GDD.md, ART_BIBLE.md, TECH.md, ROADMAP.md, RISKS.md, PLAYTEST.md
config/      input_map, quality presets (low/med/high .tres), tuning presets
src/
  core/      game_state.gd, save_system.gd, event_bus.gd, noise_bus.gd, time_slicer.gd
  input/     input_router.gd, touch_joystick.gd, touch_look.gd, control_scheme.gd
  camera/    cam_rig.gd, cam_profile.gd (Resource), cam_shake.gd
  player/    player.gd, states/{locomotion,aim,dodge,melee,interact,mount,ride,dismount,hurt}.gd, player_anim.gd
  vehicle/   moto_controller.gd, moto_tuning.gd (Resource), surface_data.gd, moto_suspension.gd, rider_rig.gd, moto_audio_synth.gd, moto_upgrades.gd
  combat/    weapon.gd, weapon_data.gd (Resource), hitscan.gd, melee_combo.gd, aim_assist.gd, feedback.gd, damage.gd
  ai/        zombie.gd, zombie_data.gd, fsm/*.gd, perception.gd, attack_slots.gd, ai_lod.gd
  ui/        hud.tscn, tuning_panel.gd, debug_overlay.gd
  levels/    test_track.tscn, combat_arena.tscn
assets/      models/, anims/, audio/, materials/, LICENSES.md
tests/       GUT birim testleri + input-replay bot testleri
scripts/     fetch_assets.ps1, fetch_godot.ps1, run_tests.ps1
tools/       (gitignore) Godot portable exe
```

---

## 2. Game Design Document (özet — docs/GDD.md'de genişler)

**Kimlik:** "Rotayı sen açarsın." Oyuncu şehrin ölü damarlarını (yollar, elektrik, telsiz, yakıt) tek tek canlandıran bir kuryedir. Days Gone'dan farkı: **güzergâh ağı** çekirdek ilerleme birimidir — her açılan güvenli rota haritada fiziksel olarak görünür (fenerler, işaretler, temizlenmiş barikatlar) ve sonraki seferleri hızlandırır/güvenli kılar.

**Ana hedef:** THE LAST EVACUATION — 5 "Konvoy Şartı" (Güç, Sinyal, Yakıt, Güvenli Rota, Hayatta Kalanlar). Her şart bir göstergeye bağlı; final konvoyu tüm şartlar eşiği geçince açılır. Sonrası: serbest oyun, kalan bölgeler, olaylar.

**Motivasyon katmanları:** kısa (5–15 dk: bir loot noktası/olay), orta (30–90 dk: upgrade/rota/kontrol noktası), uzun (konvoy şartları). Haritada her an **tek bir "sonraki anlamlı adım"** vurgusu + en fazla 3 opsiyonel işaret.

**Oturum tasarımı:** Her sığınaktan çıkışta 3 dk içinde ilk anlamlı karşılaşma garanti (Event Director kuralı). Görev adımları 5–12 dk'lık parçalara bölünür, her parça sonunda otomatik kayıt.

**Yasaklar:** günlük giriş zorunluluğu, bekleme sayaçları, gacha/loot box, zorla reklam.

### Tespit ettiğim çelişkiler ve önerdiğim çözümler
1. **Sınırlı çanta ↔ envanter angaryası yok:** Izgara/ağırlık yerine *kategori cepleri* (Mühimmat/Medikal/Malzeme/Yakıt), her cep yığın sınırlı. Dolunca fazlası motor çantasına otomatik gider. Düzenleme ekranı yok.
2. **Baked lighting ↔ dinamik şehir (sokak lambaları yanması):** Lightmap'ler sonradan değişmez. Çözüm: bölge başına 2 lightmap seti (kapalı/elektrikli), elektrik gelince set değişir + emissive materyaller + oyuncu çevresinde bütçeli 4 dinamik ışık.
3. **Gece görevi ↔ mobil ışık bütçesi:** Sürekli gün döngüsü yerine 3 ayrık zaman preseti (Şafak / Gün / Gece), her biri önceden bake'li. Görev ve uyku ile geçiş.
4. **Benzin sistemi ↔ cezalandırmama:** Yakıt bitince "rezerv modu": %40 güç, sınırsız yavaş sürüş → oyuncu asla mahsur kalmaz, ama verimsizdir.
5. **Motor ses → zombi çekme ↔ motorun keyfi:** Rölanti/düşük gazda duyulma yarıçapı küçük; agresif gaz büyük. Oyuncu "sessiz sürüş" öğrenir — ceza değil, beceri.
6. **Açık dünya özgürlüğü ↔ görev yönlendirmesi:** Görevler bölge durumuna bağlı kapılarla açılır, sıralı zorlama yok; ama "sonraki adım" her zaman tanımlı.
7. **Three-way conflict ↔ basit insan AI:** P1'de yalnızca tek Raider arketipi (devriye/nöbet/siper/kaç), zombilere tepki zorunlu.

### İlk sürümden çıkarılanlar
Gyro aim (P2), motor üstünde ateş (P3), faction diplomasisi/ticaret (P3), sürekli gün-gece döngüsü, 6 bölge (→ 1 mahalle), Screamer & Wanderer group (P1), crafting ağacı (yalnızca 4 tarif), üs NPC rutinleri, görsel özelleştirme (renk/çıkartma P3), çoklu sığınak.

---

## 3. Motosiklet sistemi (P0 — en yüksek öncelik)

### 3.1 Fizik modeli: özel kinematik "arcade-sim hibrit"
`RigidBody3D` + `VehicleBody3D` mobilde stabil/ayarlanabilir değil, iki tekerlek dengesi oynanışı bozar. Bunun yerine `CharacterBody3D` tabanlı kendi modelim; denge daima garantili, **his parametreleri ayrı**.

Durum değişkenleri: `v` (ileri hız), `v_lat` (yanal kayma), `yaw`, `ω` (yaw hızı), `φ` (lean), `pitch`, `rpm`, `gear`, `susp_front/rear`.

| Bileşen | Formül / davranış | Başlangıç değerleri |
|---|---|---|
| Hızlanma | `a = torque_curve(v/vmax) · a_max · surf.power − c_roll·v − c_air·v²` | vmax 26 m/s (94 km/h), 0→60 km/h ≈ 3.2 sn, 0→max ≈ 9 sn |
| Vites hissi | 5 sanal vites; vites geçişinde 0.12 sn tork düşüşü + RPM dip (ses ve kamera ile senkron) | — |
| Fren | Ön fren 9 m/s² (asfalt); yük öne aktarılır → ön süspansiyon dalışı `pitch += decel·0.012 rad` | Toprakta 5.5 m/s² |
| Arka fren/el freni | Arka tutuşu kırar, kontrollü kayma başlatır | — |
| Direksiyon | input `s` yumuşatma: yükselme 0.10 sn, dönüş 0.16 sn | — |
| Dönüş limiti | `ω_max(v) = min(ω_low, μ·g·grip / v)` — düşük hızda çevik, yüksek hızda geniş yarıçap | ω_low 2.4 rad/s |
| Lean | hedef `φ = atan(v·ω / g)`, max 48°, yay-sönüm (4 Hz, ζ 0.75) — *görsel ve sürücü pozunu sürer, fiziği değil* | — |
| Kayma/drift | İstenen yanal ivme > `0.85·μ·g` ise fazlası `v_lat`'a gider; tutuş `τ=0.35 sn` ile toparlar; max drift açısı 25° | Toprakta eşik düşük → kolay drift |
| Süspansiyon | Ön/arka raycast, yay k + sönüm, 0.12 m strok; gövde pitch/height bundan türetilir | — |
| Yokuş | Yerçekimi bileşeni hızlanmaya eklenir; zemin normaline hizalama slerp 10/sn | — |
| Havada | Yaw kilitli, pitch hafif kontrol; iniş sertliği süspansiyon + kamera + ses | — |

**Zemin tablosu (`SurfaceData` .tres):** asfalt μ1.0 / toprak 0.72 / çakıl 0.65 / çim 0.6 / çamur 0.45 (+%30 sürükleme). Her biri: tutuş, güç çarpanı, titreşim genliği, toz/çamur partikülü, lastik sesi. Zemin tespiti: collider'a atanmış fizik materyali / meta etiketi.

**Çarpışmalar:**
- Duvar: çarpma hızının normal bileşeni < 7 m/s → sekme + hız kaybı + kamera darbesi; ≥ 9 m/s ve açı < 35° → **düşme** (sürücü fırlatma animasyonu, 1.4 sn sonra kontrol, motor hasarı).
- Zombi: < 30 km/h → itme, motor yavaşlar, hafif yalpa; ≥ 30 km/h → zombi devrilir, motor dayanıklılığı −, %15 hız kaybı. Brute: motoru durdurur/devirir (öğretici tehdit).
- Küçük engel (kaldırım, enkaz): süspansiyon emer, < 0.25 m yükseklik geçilebilir.

**Ses → AI:** gürültü yarıçapı = rölanti 25 m → tam gaz 80 m (susturucu upgrade'i −%35). `NoiseBus`'a 0.5 sn'de bir yayınlanır.

**Yakıt:** tam depo ≈ 7 dk aktif gaz. Bitince rezerv modu.

### 3.2 Kontrol şemaları (ikisi de prototiplenir, ayarlardan seçilir)
- **A — Arcade:** sol joystick X = direksiyon; sağda büyük GAZ (basılı tut, kaydırınca yarım gaz), FREN (kısa = ön, uzun/ kaydır = arka-drift).
- **B — Assisted:** sol joystick yön *ve* hedef hız (yukarı itme miktarı); sistem gazı/freni otomatik yönetir, keskin dönüş isteğinde otomatik yavaşlar, ileri raycast ile duvara 0.8 sn kala fren yardımı. Sağda yalnızca "boost/sert gaz" ve "drift".
- Ustalaşma tavanı (her iki şemada): fren-dönüş-gaz zamanlaması, toprakta drift, gazı keserek sessiz geçiş.
- Masaüstü test: WASD + Space/Shift; gamepad de desteklenir.

### 3.3 Sürücü animasyonu (`rider_rig.gd`)
Hazır sürüş animasyonu yok → **prosedürel poz + IK** (Godot 4.6 `SkeletonModifier3D`/`TwoBoneIK3D`, yoksa kendi iki-kemik IK'm):
- Taban sürüş pozu (oturuş) + kalça lean'i takip eder, omurga ters %30 karşı-lean (gerçek sürücü gibi).
- Eller: gidon tutamak hedeflerine TwoBoneIK; gidon direksiyon açısıyla döner.
- Ayaklar: pegs hedeflerine IK; v < 1.5 m/s'de iç taraftaki ayak zemine raycast ile iner (denge).
- Hızlanma → gövde geri 4°, fren → öne 6°, viraj çıkışında merkeze yay ile dönüş.
- Baş: dönüş yönüne bakar (LookAt, ±25°).
- Düşük hız salınımı: perlin ile ±1° kalça mikro denge.

**Binme/inme:** en yakın binme noktasına (sol/sağ) 0.15 sn hizalama → 0.45 sn kalça eğrisi boyunca blend; motor kontrolü 0.35. sn'de aktif (input buffer'la gaz önceden basılabilir). Toplam ≤ 0.6 sn. Hızda inme (> 8 m/s): yuvarlanarak atlama. Kamera profilleri aynı süre içinde blend (kesme yok).

### 3.4 Motor görselleri
Parçalı sahne: gövde, depo, ön çatal (süspansiyonla kayar), arka amortisör, tekerler (hız·r ile döner + direksiyon), egzoz, far (SpotLight, upgrade ile menzil), yan çanta/arka sepet (upgrade'le **görünür olarak takılır**), susturucu parçası. Gövde lean ile yatar, tekerlek temas noktası etrafında döner (pivot zeminde).

### 3.5 Motor sesi (prosedürel)
`AudioStreamGenerator` → ateşleme frekansı `rpm/60 · silindir/2`, 3 harmonik + filtreli gürültü; gaz açık/kapalı farklı ton (yük), vites geçişinde dip, düşük RPM'de "patpat" darbe karakteri. Ek katmanlar: zemine göre lastik loop'u, kayma cıyaklaması, süspansiyon tıkırtısı, rüzgâr (hızla artar). 3D zayıflama + mesafede alçak geçiren filtre. Mobil CPU maliyeti ölçülür; > 0.4 ms ise 4 RPM örneğinin crossfade'ine geçilir (fallback).

### 3.6 Kamera (`cam_rig.gd`, tek rig, profil blend)
| Profil | Mesafe | Yükseklik | FOV | Diğer |
|---|---|---|---|---|
| Sürüş | 4.2 → 5.6 m (hızla) | 1.6 → 1.9 | 62 → 70° | look-ahead yaw = `ω·0.25` (≤15°), pozisyon gecikmesi kritik sönümlü yay 0.15 sn, rotasyon 0.2 sn, dokunma yoksa 1.2 sn sonra arkaya otomatik hizalanma |
| Yaya | 3.2 | 1.5 | 60° | omuz ofseti 0.45 m sağ |
| Nişan | 1.6 | 1.55 | 50° | omuz değiştirme, hassasiyet ayrı |
| Sürü | +1.5 m mesafe, +10° pitch | — | +4° | T0 düşman sayısı ≥ 8 iken yumuşak geçiş |
- Çarpışma: SpringArm (0.2 m marj) + 2 yan probe → dar sokakta "pop" yok; ince objeler (direk, çit) yok sayılır, saydamlaştırılır.
- Titreşim: perlin, `surface.roughness · v` ile, max 0.6°; landing/çarpma darbeleri ayrı. Ayarlardan kapatılabilir; FOV değişimi de kısılabilir (motion sickness).

### 3.7 Test pisti (`test_track.tscn`)
Uzun düz (400 m), keskin 90° viraj, geniş süpürme viraj, 3.5 m dar sokak, %8 yokuş + tepe atlaması, toprak bölüm, çamur cep, kaldırım/küçük rampa engelleri, terk edilmiş araç enkazı slalomu, 3 hedef zombi, tur zamanlayıcı. Oyun içi **tuning paneli** ile tüm `MotoTuning`/`CamProfile` değerleri canlı değiştirilip `config/`'e kaydedilir.

### 3.8 Kabul kriterleri (ölçülebilir)
- Girdiden görünür direksiyon tepkisine ≤ 2 kare.
- 0→60 km/h 3.0–3.5 sn; max hızda dar sokağa güvenli giriş için gereken fren mesafesi ≤ 35 m.
- Bot replay: piste kayıtlı 3 tur girdisi, sapma toleransıyla tamamlanmalı; kameranın oyuncuyu kaybettiği kare = 0; motorun takıldığı (v≈0, gaz>0.5, >1 sn) olay = 0.
- Binme ≤ 0.6 sn, inme ≤ 0.5 sn, kamera sıçraması (kare arası > 0.5 m) = 0.
- Sürüş sahnesinde orta segment hedef (masaüstünde Mobile renderer + 0.75 render ölçeği ile ön gösterge) frame time ≤ 16 ms.
- Playtest soruları 1, 2, 3, 8: kullanıcıdan ≥ 4/5.

---

## 4. Combat sistemi (P0 — en yüksek öncelik)

### 4.1 Yaya hareketi
Yürüme 1.8 / jog 4.2 / sprint 6.2 m/s; jog'a ivmelenme 0.12 sn, durma 0.1 sn; dönüş 720°/sn (yürürken), sprintte 360°/sn (ağırlık). Nişan alırken hareket 2.6 m/s, strafe/geri yürüme 8 yönlü blend space. Stamina: sprint, dodge, melee tüketir; boşken cezası "yorgun nefes + %20 yavaşlama", kilitlenme yok.

### 4.2 Animasyon katmanlama (`AnimationTree`)
- Alt gövde: hız + yön blend space (8 yön × walk/jog/sprint) + başlama/durma.
- Üst gövde: `Blend2` maskesi (spine yukarı) → silah tutma/nişan/ateş/reload; aim offset (yatay ±70°, dikey ±60°) + spine LookAt modifier ile kesin hedefleme.
- Hit-react, recoil: additive katman → hareketi kesmez.
- Root motion yalnızca dodge/melee için; locomotion kod kontrollü (input tepkisi önceliği).
- Geçişler: tüm durum geçişlerinde 0.08–0.2 sn blend; hiçbir kilit > 0.35 sn değil.

### 4.3 Kaçınma (dodge)
Mesafe 3 m, süre 0.45 sn, i-frame 0.08–0.30 sn, 0.32. sn'den itibaren herhangi bir eyleme iptal edilebilir, input buffer 0.15 sn. Yön: joystick yönü, yoksa geri. Silah tutuluyorken de yapılabilir; reload'u iptal etmez, duraklatır.

### 4.4 Silahlar (veri odaklı `WeaponData` .tres — 3 silah + melee)
| | Tabanca | Karabina (yarı/tam oto) | Pompalı |
|---|---|---|---|
| Şarjör | 12 | 24 | 5 (tek tek doldurma) |
| Atış aralığı | 0.18 sn | 0.11 sn | 0.85 sn (pompa animasyonu) |
| Hasar | 34 | 28 | 8 saçma × 14, düşüş 6→14 m |
| Kafa çarpanı | 2.5× | 2.0× | 1.5× |
| Geri tepme | 1.2° dikey, hızlı toparlanma | tırmanan desen (yukarı-sağ), orta toparlanma | 6° kamera kick + itme, yavaş toparlanma |
| Reload | 1.3 sn | 2.1 sn (boş: 2.6) | 0.5 sn/fişek, ateşle kesilebilir |
| Ses yarıçapı (AI) | 45 m | 60 m | 55 m |
| Kişilik | çevik, hassas | güçlü, kontrol ister | yakında yıkıcı, kalabalık açıcı |
Hitscan + iz efekti; bölgesel hasar: kafa/gövde/bacak (bacak vuruşu walker'ı topallatır/süründürür → oynanış sonucu).

**Melee (boru/pala):** 3'lü kombo (0.38/0.42/0.60 sn), her vuruşta aktif hasar penceresi, hareketle saldırı (adım ileri 0.6 m), 2. ve 3. vuruşta hedefe yumuşak yönelme (≤ 30°), dayanıklılık, son vuruş knockdown.

### 4.5 Geri bildirim yığını (her vuruş için hepsi senkron)
Namlu ışığı (1 kare OmniLight) + mesh flash, silaha özel kamera kick yayı, nişangâh açılması, isabet işareti (beyaz/öldürme kırmızı + kısa ses), düşmana özel 40 ms hit-stop (yalnızca düşman animasyonu durur → oyuncunun girdisi gecikmez), kısmi `PhysicalBone` impuls (vuruş yönüne sarsılma), pooled darbe decal'ı ve toz/kan efekti (abartısız, kararlı koyu ton), katmanlı silah sesi (transient + gövde + kuyruk; iç/dış mekâna göre kuyruk değişir). Haptic titreşim (mobil, kapatılabilir).

### 4.6 Düşman tepkileri
Tip × saldırı gücü × mevcut durum matrisi: flinch (additive), stagger (geri adım, saldırı iptal), knockdown (yere düşer, kalkış 1.2 sn), bacak kırılması (sürünme). Brute tabancaya flinch etmez, pompalıyla stagger olur → silah seçimi anlamlı.

### 4.7 Mobil nişan
- Sağ yarı ekran sürükleme = kamera; ATEŞ düğmesi basılıyken sürüklenebilir (ateş ederken nişan düzeltme).
- Aim assist (Kapalı/Düşük/Orta): hedef hitbox'ı 3° koni içindeyken hassasiyet ×0.45 (friction), hedef hareket ediyorsa açısal hızının %15'i kadar takip (magnetism), nişana girişte 8° içindeki hedefe yumuşak yönelme (opsiyonel). Kafa değil gövde merkezine — kafa vuruşu beceri olarak kalır.
- Hedef değiştirme: kamera sürüklemesi; ekstra düğme yok.
- Hassasiyet: kamera / nişan ayrı slider; joystick boyutu ve opaklık; solak modu (düğme ayna).
- HUD: sağda ATEŞ (büyük), NİŞAN, RELOAD, DODGE, ETKİLEŞİM (bağlamsal, yalnızca gerektiğinde görünür), silah değiştirme = silah ikonuna dokun/kaydır. Toplam ≤ 6 kalıcı düğme.

### 4.8 Düşmanın oyuncu etrafındaki davranışı
**Saldırı slotları:** oyuncu etrafında aynı anda en fazla 3 aktif saldırgan; diğerleri 3–5 m halkada rastgele gecikmeli yer değiştirir → düz çizgi hücumu yok, okunabilir kaos. Saldırı hazırlığı (telegraph): walker 0.45 sn, runner 0.30 sn (atılma), brute 0.9 sn (omuz hücumu, dodge ile kaçılır).

### 4.9 Combat arenası (`combat_arena.tscn`)
Bölümler: tek walker, 6'lı walker grubu, runner, brute, Raider hedef mankeni (P1'de AI'lı), alçak/yüksek siperler, açık meydan, 2 m dar koridor, kapı eşiği (darboğaz taktiği), dalga başlatıcı paneli (spawn tipi/sayısı), silah/mühimmat dolabı.

### 4.10 Kabul kriterleri
- Ateş girdisinden mermi/efekt/sese ≤ 1 kare; reload/dodge iptal pencereleri tabloya birebir.
- Hareket + nişan aynı anda: alt gövde yön, üst gövde hedef, ayak kayması görsel testte yok.
- 3 silahın kör testte ayırt edilebilmesi (yalnızca ses+kamera kick ile) — playtest sorusu 6.
- 30 aktif zombi (T0+T1 karışık) arenada frame time ≤ 16 ms (masaüstü ön gösterge), AI tick ≤ 1.5 ms/kare.
- Oyuncu 6 walker'a karşı yalnızca melee + dodge ile hasar almadan kazanabilmeli (beceri tavanı var) ama yeni oyuncu tabancayla da kazanabilmeli.

---

## 5. Zombi AI

**Mimari:** Hiyerarşik FSM (behavior tree mobil maliyet/karmaşıklık için gereksiz). Durumlar: `Idle → Wander → Suspicious → Investigate → Chase → Attack → Search → Return`, ek: `Stagger`, `Knockdown`, `Crawl`, `Feed` (atmosfer).

**Algı (`perception.gd`):** görüş konisi 110°, menzil 18 m (gündüz) / 9 m (gece), LOS raycast'leri zaman dilimli (ajan başına 0.2 sn'de bir). Şüphe ölçeri 0–1: mesafe, görünürlük, oyuncu hızı ile dolar; 0.5 = Suspicious (kafa çevirme), 1 = Chase. Ses: `NoiseBus` olayları {konum, yarıçap, öncelik, kaynak}; yarıçap içindeki ajanlar Investigate'e geçer, öncelik yüksekse hedef değiştirir.

**Takip:** `NavigationAgent3D` + RVO avoidance (birbirinin içinden geçmez), görüş kaybolunca son bilinen konuma git → 6–10 sn arama → dön. Takılma tespiti: 1.5 sn'de < 0.3 m ilerleme → yan kaçış/yeniden yol. Kapı/bina girişleri navmesh link'leri ile.

**Tipler (P0: Walker, Runner, Brute; P1: Screamer, Wanderer group)**
| | Hız | Can | Özellik |
|---|---|---|---|
| Walker | 0.9–1.4 m/s (bireysel varyasyon) | 100 | yakalama (kısa kurtulma mekaniği), bacak kırılınca sürünme |
| Runner | 5.0 m/s | 70 | atılma saldırısı, gürültüye en hızlı tepki |
| Brute | 1.6 m/s, hücumda 7 | 450 | flinch bağışıklığı, motoru durdurur |
| Screamer (P1) | 1.2 | 60 | görünce 2 sn çığlık → 60 m noise olayı; önce öldür hedefi |
Görsel çeşitlilik: 3 vücut tipi × 4 kıyafet × renk/hasar varyasyonu; yürüyüş animasyon hızı ±%15 ve 3 farklı walk döngüsü.

**Sürü / AI LOD (`ai_lod.gd`, `time_slicer.gd`) — tasarım P0'da altyapısı, tam sürü P1:**
| Katman | Mesafe | AI | Animasyon | Fizik/Gölge |
|---|---|---|---|---|
| T0 | < 25 m | 10 Hz, tam FSM, navmesh | 60 Hz, tam blend | var |
| T1 | 25–60 m | 3 Hz, basit FSM | 15 Hz | gölge yok |
| T2 | 60–150 m | grup flow-field, birey yok | düşük poly, 8 Hz | yok |
| T3 | görünmez | bölge grafiğinde soyut sürü {sayı, konum, yön} | yok | yok |
Bütçe: kare başına AI ≤ 1.5 ms; aşılırsa en uzaktakiler sonraki kareye kayar. Sürü hareketinde bireysel hız/yön gürültüsü ve tepki gecikmesi (0–0.6 sn) → yekpare kitle görünmez.

**Test:** FSM geçiş birim testleri, "takılma" bot testi (arenada 100 rastgele hedef, takılma sayısı), perf sahnesi (200 ajan, katman dağılımı ve ms ölçümü).

---

## 6. Art Direction Bible (özet — docs/ART_BIBLE.md)

**Stil:** Grounded Stylized Realism — gerçek ölçek, sadeleştirilmiş yüzey, güçlü silüet.

**Palet:** beton gri `#6E6B66`, asfalt `#3A3B3D`, yosun yeşili `#4F5B3A`, koyu orman `#2F3A2A`, pas turuncu `#A4532A`, solmuş tabela sarısı `#C9A646`, sis/gök `#A9B3B5`. Doygun renkler yalnızca oynanış okunabilirliğine ayrılır: loot parıltısı amber `#E8B04A`, tehlike kırmızısı yalnızca UI'da.

**Materyal sistemi:** Tek "world" shader: albedo atlası + triplanar kir/yağmur izi maskesi (yukarıdan aşağı akış), kenar aşınması (vertex AO/curvature), pürüzlülük varyasyonu, nesne başına ±%6 renk varyasyonu. Tüm CC0 modeller bu shader'a geçirilir → paketler arası stil uyuşmazlığı biter. Metal mat, plastik/cam parlaklığı sınırlı.

**Işık:** tek güneş (2 kaskad gölge, 60 m), LightmapGI statik, sis (derinlik + yükseklik), AgX tonemap, hafif desatürasyon + sıcak/soğuk split grading, glow yalnızca emissive'lerde. Yüksek kalitede volumetric fog/SSAO; düşükte kapalı.

**Ölçek referansları:** kapı 2.1 m, basamak 0.18 m, kaldırım 0.15 m, şerit 3.5 m, sedan 4.5 m. Her sahnede ölçek doğrulama grid'i.

**Anti-AI-slop kontrol listesi (her sahne için):** aynı sahnede karışık paket stili yok; havada/iç içe obje yok; her dağınıklığın bir hikâyesi var (neden burada?); aşınma mantıklı (pas damlama noktalarında, yosun gölge tarafında); gri tonlama değer testi (silüetler okunuyor mu); boşluk/doluluk dengesi; tekrar eden bina cephesi aynı açıdan iki kez görünmez; texel yoğunluğu tutarlı; hareket hâlinde video kaydıyla kontrol (tek ekran görüntüsü değil).

**Örnek kompozisyonlar:** (1) Garaj sığınak: tek sarı lamba, motor merkezde, kapı aralığından sisli sokak. (2) Benzinlik: yarı yıkık kanopi silüeti, devrik pompa, arkada orman sınırı. (3) Konvoy caddesi: kaybolan perspektifte terk edilmiş araç dizisi, yol ortasında karantina bariyeri.

---

## 7. Animasyon planı
- **Oyuncu:** idle(3 varyasyon), walk/jog/sprint 8 yön, start/stop, dönüş-yerinde, aim offset, ateş (3 silah), reload (3), silah değiştirme, melee kombo 3, dodge 4 yön, hit react (ön/arka/yan), loot alma (alçak/orta), kapı açma, binme/inme (sol/sağ), sürüş IK pozu, düşme/kalkma.
- **Motor:** prosedürel (lean, süspansiyon, tekerlek, gidon, gövde titreşimi, fren dalışı).
- **Zombi:** idle 3, walk 3 döngü, run, crawl, saldırı hazırlık+vuruş (tip başına), hit react 3 yön, stagger, knockdown/kalkış, yön dönüşü, ölüm (fizik + poz blend).
- **Standart:** geçiş 0.08–0.2 sn; ayak kayması < 5 cm (foot-lock); her animasyon hareket hâlinde kaydedilip gözden geçirilir; kontrol kilidi ≤ 0.35 sn.
- Kaynak: Quaternius UAL + retarget; eksikler (sürüş, motor binme) prosedürel IK ile.

---

## 8. Faction AI & Event Director (P1/P4 tasarımı)
- **Raider (P1):** Patrol → Alert → Combat (siper noktaları önceden işaretli, `cover_point` node) → Flee (can < %25 veya zombi sayısı > 4). Zombiler Raider'ları da duyar/hedefler → three-way conflict, oyuncu gürültü bırakarak (şişe, işaret fişeği, motor) sürüyü kampa çekebilir.
- **Event Director (P4):** 20 sn'de bir değerlendirme; aday olaylar koşullarla filtrelenir (bölge değerleri, ilerleme, oyuncu durumu: canı/mühimmatı), ağırlıklı seçim, olay başına cooldown + son 5 olay tekrar cezası, "yoğunluk eğrisi" (gerilim yüksekken sakin olay). Sığınaktan çıkıştan sonra ≤ 3 dk içinde ilk olay garantisi.

## 9. Dünya, bölge durumu, görevler (P2–P3 tasarımı)
- **RegionState:** ZombieThreat, HumanHostility, Resources, Infrastructure, Survivors, RouteSafety (0–100). Değişiklikler olay tabanlı (`EventBus`) ve görsel karşılıkları veri olarak tanımlı (ör. Infrastructure ≥ 50 → lightmap seti B, lamba emissive, radyo ambiyansı).
- **Rota ağı:** yol segmentleri graf; temizlenen segment "güvenli" → fenerler, boyalı işaretler, haritada yeşil çizgi; Event Director o segmentte tehdit olasılığını düşürür (sıfırlamaz).
- **İlk mahalle (Phase 2):** ~400×400 m, 6–8 keşfedilebilir iç mekân (garaj-sığınak, benzinlik, eczane, market, apartman 2 kat, tamirhane, radyo kulesi).
- **Görev zinciri M01–M10:** prompttaki sıra korunur; her görevin kalıcı sonucu tanımlı (ör. M02 → telsiz olayları açılır; M04 → kestirme rota açılır + Raider tehdidi düşer; M05 → motor tamir noktası; M08 → sürü rotası değişir; M10 → Konvoy Şartı "Güvenli Rota" %25).
- **Loot:** mekân etiketli tablolar (`LootTable` .tres: hastane→medikal ağırlıklı vb.), risk katmanı çarpanı (sürü yakınında nadir parça), yeniden dolma zamanı bölge Resources değerine bağlı.

## 10. Teknik mimari
- **Bağımsız sistemler + `EventBus` (signal hub) + `NoiseBus`.** Sistemler birbirini doğrudan referanslamaz; oyuncu durum makinesi → araç/combat'a yalnızca arayüzlerle bağlanır.
- **Veri:** `MotoTuning`, `CamProfile`, `SurfaceData`, `WeaponData`, `ZombieData`, `LootTable`, `MissionData`, `UpgradeData` — hepsi `.tres`, tasarımcı (ben/kullanıcı) kodsuz ayarlar.
- **Kayıt:** JSON, `user://save_v{n}.json`, şema sürümü + migrasyon, atomik yazma (tmp → rename), otomatik kayıt: sığınak, görev adımı, uygulama arka plana alınınca (mobilde kritik). İçerik: oyuncu/motor konumu ve durumu, envanter, upgrade'ler, görev bayrakları, RegionState'ler, temizlenmiş noktalar, rota ağı.
- **Dünya akışı (Phase 2+):** 128 m chunk'lar, `ResourceLoader.load_threaded_request` ile async; navmesh chunk başına bake.

## 11. Optimizasyon stratejisi
Hedef: orta segment Android 30 FPS stabil, güçlü cihaz 60. Bütçe (kare 33 ms): render ≤ 18, AI ≤ 1.5, fizik ≤ 2, animasyon ≤ 3, ses ≤ 1, script ≤ 3. Draw call ≤ 250, ekranda ≤ 300k üçgen, doku ASTC/ETC2, atlaslar. Mesh LOD (Godot otomatik LOD), görünürlük aralığı (HLOD), occlusion culling (bake), MultiMesh foliage/enkaz, object pooling (mermi efekti, decal, zombi), animasyon LOD (§5), gölge mesafesi kısa, render ölçeği (0.7–1.0) + FSR1 upscale. Kalite presetleri `config/` altında. **Kural:** her optimizasyon öncesi/sonrası `debug_overlay` + Godot profiler ölçümü, PERF.md'ye kayıt.

## 12. Production roadmap
| Faz | Teslim | Çıkış ölçütü |
|---|---|---|
| **P0a Motosiklet** | test_track, fizik, kontrol A/B, kamera, sürücü IK, prosedürel ses, tuning paneli | §3.8 |
| **P0b Combat** | combat_arena, yaya hareket, 3 silah + melee, dodge, aim assist, Walker/Runner/Brute FSM | §4.10 |
| P0c Entegrasyon | bin-in akışı arenaya bağlı mini senaryo: motorla gel → loot → gürültü → kaç | kesintisiz, kilitsiz geçiş |
| P1 Düşman zekâsı + birleşik oynanış | perception/noise tam, Raider, Screamer, loot+envanter, kayıt | 15 dk dikey dilimin taslağı oynanır |
| P2 İlk mahalle (Phase 2) | sanat yönetimli 400 m bölge, iç mekânlar, ilk görev zinciri M01–M05 | "sadece gezmek için" testi |
| P3 Derinlik | upgrade'ler, sığınak görsel gelişimi, RegionState, kalıcı değişim | sonraki oturum değişiyor mu |
| P4 Dinamik dünya | Event Director, sürü T2/T3, faction etkileşimi | aynı rota farklı deneyim |
| P5 Polish | animasyon/ses/UI/kamera | "tamamlanmış ürün parçası" görünümü |
| P6 Mobil QA | Android export, cihaz profili, kontrol ayarı | hedef cihazda 30 FPS stabil |
| P7 İçerik | yeni bölgeler, M06–M10, konvoy | yalnızca önceki fazlar kalite eşiğinde |

**Bu turdaki iş: docs/ + P0a + P0b (+ zaman kalırsa P0c).**

## 13. Risk analizi
| Risk | Etki | Azaltma / basitleştirme |
|---|---|---|
| Prosedürel sürücü IK doğal görünmezse | Yüksek | Sabit sürüş pozu + yalnızca kalça/omurga lean (IK'sız) fallback |
| CC0 asset'lerin "ucuz" görünmesi | Yüksek | Ortak shader + ışık/grading; P0 sonunda kullanıcı onayı; gerekirse karakterlerde stilize "silüet öncelikli" yön |
| Dokunmatik nişan hissi | Yüksek | Aim assist presetleri, ateş-sürükle, gerçek cihaz testi P6'dan öne çekilebilir |
| Prosedürel motor sesi yapay gelirse | Orta | CC0 RPM örnekleri crossfade fallback |
| Sürü performansı (GDScript) | Orta | T2/T3 tek düğümde toplu güncelleme, MultiMesh; gerekirse yalnızca horde sim GDExtension |
| Android export kurulumu kullanıcıya yük | Orta | Ben script'lerim (JDK + SDK komut satırı); kullanıcı yalnızca telefonu USB ile bağlar |
| Godot Mobile renderer görsel sınırları | Düşük-Orta | Lightmap ağırlıklı ışık, Forward+ yalnızca masaüstü önizleme için |
| Kapsam şişmesi | Yüksek | Faz çıkış ölçütleri sağlanmadan sonraki faza geçilmez |

## 14. Playable vertical slice (Phase 1–2 sonu hedefi)
Prompttaki 15 dakikalık akış birebir: garaj sığınak → telsiz → benzinlik (yakıt + mekanik parça) → gürültüyle gelen zombi grubu + uzaktan geçen Raider devriyesi → kaçış → kestirme keşfi → dönüş → yan çanta upgrade'i (motorda görünür, kapasite artar) → yeni telsiz sinyali. İçerik: 1 mahalle, 1 motor, 3 silah + melee, Walker/Runner/Brute/Screamer, 1 Raider arketipi, 4 crafting tarifi, 3 upgrade (çanta, susturucu, süspansiyon), kayıt/yükleme.

---

## 15. Bu turun uygulama sırası (P0)
1. `change_directory` → `C:\Users\USER\Desktop\last-route` (yeni klasör).
2. `scripts/fetch_godot.ps1`: Godot 4.6+ portable'ı `tools/`'a indir (onayınla). `scripts/fetch_assets.ps1`: CC0 paketler + LICENSES.md.
3. `docs/`: GDD, ART_BIBLE, TECH, ROADMAP, RISKS, PLAYTEST (bu planın genişletilmiş hâli).
4. İskelet: `project.godot` (Mobile renderer, input map, autoload: EventBus/NoiseBus/GameState), `config/` presetleri, debug overlay.
5. Kamera rig + girdi yönlendirici (touch + klavye/gamepad).
6. Motosiklet fiziği → süspansiyon → zemin tablosu → test pisti (gri kutu) → tuning paneli → bot replay testi.
7. Sürücü rig + binme/inme + prosedürel motor sesi.
8. Yaya hareket + AnimationTree katmanlama + dodge.
9. Silahlar + geri bildirim yığını + aim assist + melee.
10. Zombi FSM + perception + saldırı slotları + combat arena.
11. Atmosfer geçişi (ortak shader, environment, ışık) her iki test sahnesi için.
12. Doğrulama (§16), sonuç raporu: ne çalışıyor, ne test edildi, kalan sorunlar, ekran görüntüleri.

## 16. Doğrulama
- **Statik:** `godot --headless --check-only` tüm script'ler; `--headless --quit-after 300` her sahne hatasız yükleniyor.
- **Birim (GUT, `tests/`):** hız eğrisi ve 0→60 süresi, ω_max(v), lean limitleri, zemin çarpanları, silah atış aralığı/mühimmat/reload iptali, dodge i-frame penceresi, FSM geçişleri, saldırı slotu sınırı, kayıt round-trip.
- **Bot/replay:** kayıtlı girdilerle pist turu (takılma = 0, kamera kaybı = 0), arena dalgası (zombi takılma sayısı).
- **Görsel:** headless olmayan kısa çalıştırmada ekran görüntüsü/`--write-movie` klip alıp kendim inceleyeceğim; kullanıcıya gösterilecek.
- **Performans:** debug overlay + profiler, masaüstünde Mobile renderer ile ön gösterge; gerçek mobil sayılar yalnızca P6'da cihazda — o zamana kadar "telefonda çalışıyor" iddia edilmeyecek.
- **Kullanıcı playtest:** docs/PLAYTEST.md'deki 10 soru (1–5 puan); < 4 alan her madde önem derecesiyle (Kritik/Yüksek/Orta/Düşük) kayıt → düzeltme → tekrar test.
