# Terraform — nauka: odtwarzamy projekt 3-tier w Terraformie

Cel: odtworzyć architekturę podobną do AWS-3tier-java-app, zadanie po zadaniu,
uczysz się Terraforma pisząc kod SAM. Źródła: docs Terraforma + docs providera
AWS. Jak utkniesz 30 min → wracasz z konkretnym błędem.

Zasada projektu: **budowa kumulatywna** — infrastruktura z poprzednich zadań
ZOSTAJE i rośnie o nowe elementy. Destroy tylko: (a) na koniec sesji nauki /
przerwę, (b) gdy coś trzeba posprzątać. Po każdym destroy + apply wszystko
wstaje z powrotem, ale publiczne IP się zmieniają.

Stan na 2026-09-07: zadanie 1 zaliczone (pełny cykl z destroy — AWS puste).
terraform 1.16, aws-cli 2.36, provider aws ~> 6.62. Aktualne: **zadanie 2**.

---

## Zadanie 1 (ZALICZONE 2026-09-07): fundament sieciowy

VPC 10.0.0.0/16 (tagi Name + Project=terraform-3tier), 2 publiczne subnety
(10.0.1.0/24, 10.0.2.0/24, map_public_ip_on_launch), 2 prywatne
(10.0.11.0/24, 10.0.12.0/24), po 2 w różnych AZ, IGW, route table publiczna
(0.0.0.0/0 → IGW) i prywatna (bez NAT), 4 asocjacje. Outputs: vpc_id,
subnet_pub_ids.

---

## Zadanie 2 (AKTUALNE): bastion + security groups

### Krok 0 — porządki (zanim cokolwiek)
- [ ] .gitignore: `.tfstate` → `*.tfstate` (obecny wzór NIE ignoruje
      terraform.tfstate — git status to pokazuje)
- [ ] zacommitować wiszące zmiany: .gitignore + outputs.tf
- [ ] `terraform apply` — sieć z zadania 1 wstaje (12 to add)

### Krok 1 — klucz SSH (lokalnie, nie w Terraformie)
```
ssh-keygen -t ed25519 -f ~/.ssh/terraform-3tier
```
Prywatny klucz zostaje na dysku i NIGDY nie idzie do gita. Publiczny (.pub)
idzie do AWS przez resource `aws_key_pair` + funkcja `file()`.

### Co ma powstać
- `aws_key_pair` — publiczny klucz
- `aws_security_group` bastionu: ingress tcp/22 TYLKO z `var.my_ip`
  (CIDR /32 — swoje IP sprawdź np. `curl ifconfig.me`); egress domyślny
- `data "aws_ami"` ubuntu — masz gotowy blok w notatkach z pierwszej sesji
  (Canonical 099720109477, noble 24.04) — wraca do main.tf
- `aws_instance` bastion: t3.micro przez `var.instance_type`,
  publiczny subnet 1, publiczny IP (w docs aws_instance znajdź argument —
  i czym różni się od map_public_ip_on_launch w subnecie), `key_name`,
  SG, tagi Name (var.instance_name) + Project
- output: publiczny IP bastionu
- zmienne: `instance_type`, `instance_name` wracają do gry; nowa `my_ip`

### Bloki
```
aws_key_pair        x1
aws_security_group  x1
data "aws_ami"      x1
aws_instance        x1
```

### Workflow + test
init → fmt → validate → plan → apply → **ssh -i ~/.ssh/terraform-3tier ubuntu@IP**
(user: ubuntu, nie root) → sprawdzić w konsoli EC2/SG → zostawiasz stojące
(kumulatywnie) albo destroy, jak kończysz sesję.

### Definition of done
- [ ] plan pokazuje **15 to add** (12 sieci + 3 nowe; data się nie liczy)
- [ ] ssh wchodzi na bastiona
- [ ] SG w konsoli: dokładnie jedna reguła inbound (22/TCP z twojego IP)
- [ ] umiesz odpowiedzieć na pytania kontrolne 9–12

### Bonus dla ambitnych
user_data instalujący nginx + ingress 80/TCP w SG → `curl http://IP`.
Zobaczysz przy okazji apply aktualizujący istniejący zasob (~) zamiast tworzący.

### Koszt
t3.micro = free tier (750h/mies., jedna instancja = max 744h — mieści się).
Sieć darmowa. Po zakończeniu sesji destroy.

---

## Pytania kontrolne (bank rośnie z każdym zadaniem)
1. Po co `terraform.tfstate`, co jest w środku, czemu nie na GitHub?
2. `plan` vs `apply`; co się stanie przy apply bez zmian w kodzie?
3. Czemu prywatne subnety w oryginale miały NAT, a tu go nie ma?
4. Po co `outputs`?
5. `data` block vs `resource` block — różnica? (na żywo w zadaniu 2)
6. `module` vs surowe `resource`? Co jest w środku modułu VPC?
7. Czy kolejność zasobów w pliku ma znaczenie? (graf zależności)
8. Czemu przypinać wersje providera? Co znaczy `~> 5.92`?
9. Dlaczego 22/TCP otwarte na 0.0.0.0/0 to zły pomysł? Co znaczy /32?
10. Czemu do `aws_key_pair` idzie klucz publiczny, a prywatny zostaje
    lokalnie? Co by było, gdyby prywatny wylądował w repo?
11. Po co bastion w architekturze 3-tier — jak dzięki niemu wejdziesz
    kiedyś na EC2 w prywatnym subnecie?
12. `map_public_ip_on_launch` (subnet) vs `associate_public_ip_address`
    (instancja) — czym się różnią?

Pytania 1–8 do odrobienia ustnie na najbliższej sesji (jak na rozmowie).

---

## Koszty (pilnuj tego!)
- **NIE free tier**: NAT Gateway (~$33/mies + dane), NLB/ALB (~$16/mies),
  Transit Gateway — pomijamy albo tworzymy na chwilę i od razu destroy
- EC2 t3.micro i RDS db.t3.micro = 750h/mies w free tier (12 mies. od
  założenia konta) — sprawdzać w Billing
- Zasada: na koniec sesji nauki destroy

## Kolejne zadania
- **3**: RDS MySQL (free tier) + db_subnet_group na prywatnych subnetach
- **4**: S3 + IAM role dla EC2 + alarm CloudWatch
- **5**: ALB + Auto Scaling Group + launch template (uwaga na koszty!)
- **6**: refaktor na moduły + remote state w S3

## TODO porządkowe
- [ ] pilne: wzór w .gitignore (`.tfstate` → `*.tfstate`)
- [ ] zacommitować .gitignore + outputs.tf
