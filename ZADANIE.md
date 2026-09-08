# Terraform — nauka: odtwarzamy projekt 3-tier w Terraformie

Cel: odtworzyć architekturę podobną do AWS-3tier-java-app, zadanie po zadaniu,
uczysz się Terraforma pisząc kod SAM. Źródła: docs Terraforma + docs providera
AWS. Jak utkniesz 30 min → wracasz z konkretnym błędem.

Zasada projektu: **budowa kumulatywna** — infrastruktura z poprzednich zadań
ZOSTAJE i rośnie o nowe elementy. Destroy tylko: (a) na koniec sesji nauki /
przerwę, (b) gdy coś trzeba posprzątać. Po każdym destroy + apply wszystko
wstaje z powrotem, ale publiczne IP się zmieniają.

Stan na 2026-09-08: zadania 1 i 2 zaliczone (bastion stoi, ssh działa).
Aktualne: **zadanie 3**. terraform 1.16, aws-cli 2.36, provider aws ~> 6.62.

---

## Zadanie 1 (ZALICZONE 2026-09-07): fundament sieciowy

VPC 10.0.0.0/16 (Name + Project), 2 publiczne subnety (10.0.1.0/24,
10.0.2.0/24, map_public_ip_on_launch), 2 prywatne (10.0.11.0/24,
10.0.12.0/24), po 2 w AZ, IGW, RT publiczna (0.0.0.0/0 → IGW) i prywatna
(bez NAT), 4 asocjacje. Outputs: vpc_id, subnet_pub_ids.

## Zadanie 2 (ZALICZONE 2026-09-08): bastion + security groups

aws_key_pair (ed25519, pathexpand+file), SG bastionu z osobnymi regułami
(ingress 22/TCP z var.my_ip /32, egress all "-1"), data aws_ami Amazon
Linux 2023 (owners=amazon), instancja t3.micro w publicznym subnecie 1,
output publicznego IP. Test ssh (ec2-user) przeszedł.

---

## Zadanie 3 (AKTUALNE): RDS MySQL — warstwa danych

### Krok 0 — porządki
- [ ] zacommitować kod zadania 2 (portfolio!)
- [ ] `terraform plan` — ma pokazać no changes (infra z zadania 2 stoi);
      jak coś brakuje → apply
- [ ] plik `terraform.tfvars`: przenieś tam `my_ip` (usuń default
      z variables.tf — prawdziwe IP nie powinno siedzieć w repo) + będzie
      tam hasło do bazy (punkt niżej)
- [ ] dodać `terraform.tfvars` do .gitignore **zanim** wpiszesz tam cokolwiek

### Co ma powstać
- `aws_db_subnet_group` na 2 prywatnych subnetach — RDS wymaga subnetów
  w co najmniej 2 AZ (dowieziesz z docs czemu)
- `aws_security_group` dla RDS: ingress 3306/TCP **z SG bastionu**, nie z
  CIDR — w `aws_vpc_security_group_ingress_rule` istnieje argument
  `source_security_group_id` (SG-to-SG: „wpuszczaj ruch od maszyn, które
  mają tamten SG")
- `aws_db_instance`:
  - engine mysql, engine_version 8.0.x (sprawdź w docs aktualną 8.0)
  - instance_class db.t3.micro (free tier), allocated_storage = 20
  - db_name, username, password — z variables; **password: sensitive,
    BEZ defaulta, wartość w terraform.tfvars** (który jest gitignored)
  - publicly_accessible = false, multi_az = false
  - skip_final_snapshot = true — najpierw przeczytaj w docs, co to jest
    final snapshot i co się stanie przy destroy bez skip
- output: `endpoint` RDS (nigdy hasło!)

### Bloki
```
aws_db_subnet_group                     x1
aws_security_group                      x1
aws_vpc_security_group_ingress_rule     x1   # 3306 z SG bastionu
aws_db_instance                         x1
```

### Nowe zmienne
`db_name`, `db_username`, `db_password` (sensitive = true, bez defaulta)

### Workflow + test
fmt → validate → plan → apply → **test z bastiona** → destroy na koniec sesji

Apply potrwa kilka–kilkanaście minut: RDS to prawdziwy serwer, Terraform
pollinguje API aż stan `available`. To ta „wolna" strona chmury, o której
była mowa przy zadaniu 2.

Test łączności (ssh na bastion, potem):
```
timeout 3 bash -c '</dev/tcp/ENDPOINT:3306' && echo "PORT OK"
```
Opcjonalnie pełny klient na bastionie:
`sudo dnf install -y mariadb105` → `mysql -h ENDPOINT -u USERNAME -p`

### Definition of done
- [ ] plan pokazuje **4 to add** (bastion i sieć już stoją — kumulatywnie)
- [ ] test 3306 z bastiona przechodzi (cały łańcuch: routing + SG-to-SG)
- [ ] konsola RDS: subnety prywatne, Publicly accessible = No
- [ ] destroy na koniec sesji przechodzi bez tworzenia snapshotu

### Koszt
db.t3.micro = osobne 750h/mies. w free tier (nie dzieli się z EC2), 20 GiB
gp2 się mieści. Ale RDS stale włączone zjada te godziny — na koniec sesji
destroy, odtworzenie to jedna komenda.

### Bonus dla ambitnych
W `aws_db_instance` istnieje `manage_master_user_password = true` —
hasło ląduje w Secrets Managerze. Pełne podejście do sekretów robimy
w zadaniu 4; teraz wystarczy zmienna sensitive + tfvars.

---

## Pytania kontrolne (bank; użytkownik odkłada na później — wracać przy okazji)
1. Po co `terraform.tfstate`, co jest w środku, czemu nie na GitHub?
2. `plan` vs `apply`; co się stanie przy apply bez zmian w kodzie?
3. Czemu prywatne subnety w oryginale miały NAT, a tu go nie ma?
4. Po co `outputs`?
5. `data` block vs `resource` block — różnica?
6. `module` vs surowe `resource`? Co jest w środku modułu VPC?
7. Czy kolejność zasobów w pliku ma znaczenie? (graf zależności)
8. Czemu przypinać wersje providera? Co znaczy `~> 5.92`?
9. Dlaczego 22/TCP otwarte na 0.0.0.0/0 to zły pomysł? Co znaczy /32?
10. Czemu klucz publiczny idzie do AWS, a prywatny zostaje lokalnie?
11. Po co bastion w architekturze 3-tier?
12. `map_public_ip_on_launch` vs `associate_public_ip_address`?
13. Czemu RDS wymaga subnet group z subnetami w ≥2 AZ?
14. Jak działa SG-to-SG (`source_security_group_id`) i czemu lepsze od CIDR?
15. Czemu `sensitive = true` NIE wystarcza jako ochrona hasła?
    (wskazówka: co ląduje w terraform.tfstate w plaintext)
16. Co to final snapshot i czemu `skip_final_snapshot = true` przy nauce?

---

## Koszty (pilnuj tego!)
- **NIE free tier**: NAT Gateway (~$33/mies + dane), NLB/ALB (~$16/mies),
  Transit Gateway — pomijamy albo tworzymy na chwilę i od razu destroy
- Free tier: EC2 t3.micro 750h, RDS db.t3.micro 750h (osobno), 20 GiB gp2
- Zasada: na koniec sesji nauki destroy

## Kolejne zadania
- **4**: S3 + IAM role dla EC2 + alarm CloudWatch
- **5**: ALB + Auto Scaling Group + launch template (uwaga na koszty!)
- **6**: refaktor na moduły + remote state w S3

## TODO porządkowe
- [ ] commit kodu zadania 2
- [ ] terraform.tfvars (my_ip + db_password) + wpis do .gitignore
- [ ] usunąć default my_ip z variables.tf (do tfvars)
