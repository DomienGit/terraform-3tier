# Terraform — nauka: odtwarzamy projekt 3-tier w Terraformie

Cel: odtworzyć architekturę podobną do AWS-3tier-java-app, zadanie po zadaniu,
uczysz się Terraforma pisząc kod SAM. Źródła: docs Terraforma + docs providera
AWS. Jak utkniesz 30 min → wracasz z konkretnym błędem.

Zasada projektu: **budowa kumulatywna** — infrastruktura z poprzednich zadań
ZOSTAJE i rośnie o nowe elementy. Destroy tylko: (a) na koniec sesji nauki /
przerwę, (b) gdy coś trzeba posprzątać. Po każdym destroy + apply wszystko
wstaje z powrotem, ale publiczne IP się zmieniają.

Stan na 2026-09-21: zadania 1–4 zaliczone. Aktualne: **zadanie 5 (ALB+ASG,
pierwszy płatny zasób — sesja z zegarkiem!)**.

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

## Zadanie 3 (ZALICZONE 2026-09-13): RDS MySQL — warstwa danych

db_subnet_group na 2 prywatnych subnetach, SG-to-SG 3306 (referenced_
security_group_id), db.t3.micro / 20 GiB / 8.0.46, sekrety w gitignorowanym
terraform.tfvars (db_password sensitive), test: `ssh -v -p 3306` →
`Connection established`. Weryfikacja CLI: prywatne subnety, Publicly
Accessible = No.

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
sudo dnf install -y nmap-ncat          # raz; bash AL2023 nie ma /dev/tcp!
nc -zv ENDPOINT 3306                   # świeży ENDPOINT z terraform output
```
Uwaga z lasu: bash na AL2023 jest budowany bez net-redirections, więc trik
`</dev/tcp/host/port>` tam nie działa (mylący błąd "No such file or directory").
Opcjonalnie pełny klient: `sudo dnf install -y mariadb105` → `mysql -h ENDPOINT -u USER -p`

### Definition of done
- [x] plan pokazał 21 to add, apply przeszedł
- [x] test 3306 z bastiona: `Connection established` (ssh -v)
- [x] weryfikacja: subnety prywatne, Publicly accessible = No
- [ ] destroy na koniec sesji (zasada stała)

### Koszt
db.t3.micro = osobne 750h/mies. w free tier (nie dzieli się z EC2), 20 GiB
gp2 się mieści. Ale RDS stale włączone zjada te godziny — na koniec sesji
destroy, odtworzenie to jedna komenda.

### Bonus dla ambitnych
W `aws_db_instance` istnieje `manage_master_user_password = true` —
hasło ląduje w Secrets Managerze. Pełne podejście do sekretów robimy
w zadaniu 4; teraz wystarczy zmienna sensitive + tfvars.

---

## Zadanie 4 (ZALICZONE 2026-09-21): S3 + IAM role dla EC2 + alarm CloudWatch

Bucket (globalna nazwa, force_destroy, public_access_block, versioning),
rola z trust (ec2.amazonaws.com) + least-privilege permissions (ListBucket
na bucketu, Get/PutObject na /*), instance profile podpięty do bastiona,
alarm CPUUtilization. Test: `aws sts get-caller-identity` z bastiona zwrócił
assumed-role, `s3 cp`/`s3 ls` działają bez żadnych kluczy, alarm w stanie OK.
Lekcje z review: referencja bez cudzysłowów vs `${}` w stringu;
`aws_iam_role_policy_attachment` (nie policy_attachment), dimensions jako
mapa `InstanceId = ...`.

Wzorzec mistrzowski: „instancja dostaje uprawnienia przez IAM role, nie
przez klucze". Bastion — bez żadnych credentials — nauczy się pisać do S3.

### Krok 0 — porządki
- [ ] `terraform plan` — no changes (infra stoi) albo apply po destroy
- [ ] commit zadania 3 (`Add RDS MySQL (task 3)`) jeśli jeszcze nie zrobiony
- [ ] na bastionie: `curl -s --max-time 5 https://ifconfig.me` — domknąć
      loose end z zadania 3 (internet → przyda się przy teście CLI)

### Co ma powstać
- `aws_s3_bucket` — uwaga: nazwa bucketu musi być unikalna **globalnie
  w całym AWS**, nie tylko na Twoim koncie → zmienna `bucket_name`
  z defaultem np. `terraform-3tier-twoj-login`; dodaj `force_destroy = true`
  (przeczytaj w docs po co — ułatwi destroy; zrozum, czemu w produkcji
  ostrożnie z tym argumentem)
- `aws_s3_bucket_public_access_block` — wszystkie 4 flagi na true
  (blokada dostępu publicznego; habit bezpieczeństwa)
- `aws_s3_bucket_versioning` — konfiguracja jako OSOBNY zasób (ten sam
  wzorzec, co osobne reguły SG w zadaniu 2)
- `data "aws_iam_policy_document"` x2:
  - **trust policy** (kto może wcielić się w rolę): Service
    `ec2.amazonaws.com`, action `sts:AssumeRole`
  - **permissions policy** (co rolka może): least privilege na Twoim
    buckecie — `s3:ListBucket` na ARN bucketu, `s3:GetObject` +
    `s3:PutObject` na ARN z `/*` (subtelność S3: lista na buckecie,
    obiekty na `/*` — zapisz sobie tę różnicę)
- `aws_iam_role` (assume_role_policy z trust), `aws_iam_policy` (policy
  z permissions), `aws_iam_role_policy_attachment`
- `aws_iam_instance_profile` + w `aws_instance` bastionu nowy argument
  `iam_instance_profile` (to będzie `~` — update in place)
- `aws_cloudwatch_metric_alarm`: CPUUtilization bastionu (namespace
  `AWS/EC2`, dimension InstanceId, np. >60% przez 2 okresy po 300 s)

### Bloki
```
aws_s3_bucket                         x1
aws_s3_bucket_public_access_block     x1
aws_s3_bucket_versioning              x1
aws_iam_role                          x1
aws_iam_policy                        x1
aws_iam_role_policy_attachment        x1
aws_iam_instance_profile              x1
aws_cloudwatch_metric_alarm           x1
data "aws_iam_policy_document"        x2
```

### Workflow + test (to jest serce zadania)
fmt → validate → plan → apply → **na bastionie, bez żadnego aws configure**:
```
aws sts get-caller-identity    # ma pokazać assumed-role/... — tożsamość!
aws s3 cp /etc/hostname s3://TWOJ-BUCKET/test.txt
aws s3 ls s3://TWOJ-BUCKET
```
AWS CLI sam bierze credentials z instance metadata — o to chodzi w całym
zadaniu. Żaden klucz nigdy nie leży na dysku instancji.

### Definition of done
- [x] plan: 29 to add (od zera po destroy), apply przeszedł
- [x] `get-caller-identity` z bastionu zwraca assumed-role
- [x] `s3 cp` i `s3 ls` działają z bastionu
- [x] alarm w stanie OK (realny datapoint CPU)
- [ ] destroy na koniec sesji (zasada stała)

### Koszt
S3 = grosze (free tier 5 GB / 12 mies.), IAM darmowe, alarm ~$0.10/mies.
(1 szt. — pomijalne, ale to pierwszy zasób poza free tier)

### Bonus dla ambitnych
- SSE: `aws_s3_bucket_server_side_encryption_configuration` (AES256)
- SNS topic + email w `alarm_actions` — prawdziwy mail przy alarmie

---

## Zadanie 5 (AKTUALNE): ALB + Auto Scaling — warstwa aplikacji

**SEJA Z ZEGARKIEM:** ALB płaci się za godziny istnienia (~$0.025/h). Plan:
kod → validate → review u mnie → apply → testy → **destroy w TEJ sesji**.
Całość < $1. Nie zostawiamy ALB na noc.

### Decyzja architektoniczna (do opowiedzenia jak na rozmowie)
Instancje app stawiamy w **publicznych** subnetach — nie mamy NAT Gateway
(~$33/mies.), a user_data musi ściągnąć nginx z internetu. Bezpieczeństwo
odrabia SG: port 80 wyłącznie od ALB (SG-to-SG), SSH wyłącznie od bastiona.
W produkcji: prywatne subnety + NAT (tak było w projekcie java-app). To jest
kompromis koszt/bezpieczeństwo — świadomy i czasowy.

### Co ma powstać
- `aws_launch_template` — przepis na klona instancji app:
  AMI (ten sam data source), t3.micro, `iam_instance_profile` — **reużyj
  istniejącego profilu** (instancje ASG dostaną S3 bez żadnej akcji!),
  app SG, klucz bastionowy, `user_data` (patrz niżej)
- `aws_lb` — application load balancer, internet-facing, w 2 publicznych
  subnetach, z własnym SG (ingress 80/TCP z 0.0.0.0/0 — to jest drzwi
  dla świata; egress: ALB musi móc dobić do targetów na 80 — pomyśl:
  minimalnie czy all; objaw zbyt ciasnego egress = 504 w przeglądarce)
- `aws_lb_target_group` — HTTP :80, target_type instance,
  health_check na path "/"
- `aws_lb_listener` — HTTP :80, forward do target group
- `aws_autoscaling_group` — 2 publiczne subnety (vpc_zone_identifier),
  min 2 / max 3 / desired 2, `health_check_type = "ELB"`,
  `target_group_arns`, zagnieżdżony blok `launch_template`
  (id + `version = "$Latest"`), tag Name z `propagate_at_launch = true`
- output: `lb_dns_name`

### user_data — wzór heredoc w HCL
```
user_data = <<-EOF
  #!/bin/bash
  dnf install -y nginx
  ...strona index.html z hostnameem instancji...
  ...echo "boot $(hostname) $(date)" | aws s3 cp - s3://BUCKET/boot-$(hostname).txt
  systemctl enable --now nginx
EOF
```
Dwie rzeczy ma robić: (1) strony WWW z hostnameem — po to, żeby w teście
widać było ROTACJĘ między instancjami, (2) boot-log do S3 — dowód, że rola
działa na instancjach, które ASG postawił SAM (nikt im niczego nie klikał).

### Bloki
```
aws_launch_template        x1
aws_security_group         x2  (alb_sg, app_sg) + reguły:
                              alb: 80/TCP z 0.0.0.0/0 (+ egress — patrz wyżej)
                              app: 80/TCP od alb_sg (SG-to-SG!),
                                   22/TCP od bastion_sg (SG-to-SG!)
aws_lb                     x1
aws_lb_target_group        x1
aws_lb_listener            x1
aws_autoscaling_group      x1
```

### Testy (po apply — instancje wstają ~2-3 min z user_data)
1. `terraform output -raw lb_dns_name` → przeglądarka/curl, kilka razy
   odśwież → **hostname zmienia się** między 2 instancjami = rotacja ALB
2. `aws s3 ls s3://terraform-3tier-domiendev/` → boot-logi od obu instancji
3. (demo self-healing, jeśli zdążysz) Terminate jednej instancji w konsoli
   → za ~2-3 min ASG stawia replacement → nowy boot-log w bucketcie

### Definition of done
- [ ] validate + mój review PRZED apply (nie płacimy za poprawki!)
- [ ] rotacja hostnamów w przeglądarce działa
- [ ] boot-logi obu instancji w S3
- [ ] destroy W TEJ SESJI + konsola pusta (też ALB!)

### Koszt (matematyka sesji)
ALB ~$0.025/h × kilka godzin + 2× t3.micro (free tier) ≈ **całość < $1**,
pod warunkiem destroy przed końcem dnia.

### Bonus (jeśli czas)
`aws_autoscaling_policy` (target_tracking, CPU ~30%) + `stress-ng` na
jednej instancji przez bastiona → obserwuj scale-out w konsoli ASG (~10 min).

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
17. Czemu EC2 dostaje uprawnienia przez IAM role, a nie przez access key
    w `aws configure` na instancji?
18. Trust policy vs permissions policy — która mówi „kto", która „co"?
19. Czemu nazwa bucketu S3 musi być unikalna globalnie w całym AWS?
20. Least privilege — czemu własna polityka na 3 akcje lepsza od
    AmazonS3FullAccess?
21. Po co launch template — czemu ASG nie tworzy instancji bezpośrednio?
22. Health check typu EC2 vs ELB w ASG — kiedy instancja uznawana za chora
    w każdym z trybów?
23. Skąd ALB wie, do których instancji kierować ruch? (target group,
    subnety ASG, AZ)
24. Czemu w produkcji app siedzi w prywatnych subnetach z NAT, a u nas
    stoi w publicznych? (kompromis koszt/bezpieczeństwo)

---

## Koszty (pilnuj tego!)
- **NIE free tier**: NAT Gateway (~$33/mies + dane), NLB/ALB (~$16/mies),
  Transit Gateway — pomijamy albo tworzymy na chwilę i od razu destroy
- Free tier: EC2 t3.micro 750h, RDS db.t3.micro 750h (osobno), 20 GiB gp2
- Zasada: na koniec sesji nauki destroy

## Kolejne zadania
- **6**: refaktor na moduły + remote state w S3

## TODO porządkowe
- [ ] commit zadania 4: `Add S3 + IAM role + CloudWatch alarm (task 4)`
- [ ] opcjonalnie: opisowe nazwy zamiast test_policy/test_profile/
      test_alarm/example-attach (czytelność w konsoli)
