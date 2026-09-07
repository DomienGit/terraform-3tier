# Terraform — nauka na przykładzie projektu 3-tier

Cel: opanować Terraform, budując stopniowo (i tanio) architekturę podobną do
projektu AWS-3tier-java-app. Kod piszę SAM — źródła: docs Terraforma +
docs providera AWS. Jak utknę 30 min → wracam z konkretnym błędem.

Stan na 2026-09-03: teraform + repo git działają, init zrobiony,
apply był uruchamiany (jest tfstate). Pliki wciąż z tutoriala HashiCorp —
do przerobienia wg zadania 1 poniżej.

---

## Zadanie 1 (AKTUALNE): fundament sieciowy

### Sprzątanie main.tf
- zostaw: `provider "aws"` (region z `var.region` — już dobrze)
- usuń na ten moment: `module "vpc"`, `aws_instance`, `data "aws_ami"`
  (wzorzec data-AMI jest dobry — wróci w zadaniu 2 przy bastionie)
- `versions.tf` — zostaje, konwencja nazwy: trzymam się `versions.tf`

### Co ma powstać
- VPC `10.0.0.0/16`, tagi `Name` + `Project=terraform-3tier`,
  `enable_dns_hostnames = true`, `enable_dns_support = true`
- 2 publiczne subnety (`10.0.1.0/24`, `10.0.2.0/24`) w 2 różnych AZ,
  `map_public_ip_on_launch = true`
- 2 prywatne subnety (`10.0.11.0/24`, `10.0.12.0/24`) też w 2 AZ
- Internet Gateway + route table z trasą `0.0.0.0/0 → IGW`,
  powiązana z publicznymi subnetami
- Osobna route table dla prywatnych (bez NAT!), powiązana z nimi

### Potrzebne bloki resource (argumenty wyprowadzam sam z docs)
```
aws_vpc                       x1
aws_subnet                    x4
aws_internet_gateway          x1
aws_route_table               x2
aws_route_table_association   x4
```
Bonus: wersja z `for_each` zamiast 4x kopiuj-wklej subneta.

### Variables / outputs
- variables: `region`, `vpc_cidr`
- outputs: `vpc_id`, lista ID publicznych subniet

### Obowiązkowy workflow (zawsze w tej kolejności)
```
terraform init → fmt → validate → plan → apply → (konsola AWS) → destroy → (konsola AWS)
```
Przy plan: przeczytać CAŁY output przed `yes`.

### Definition of done
- [ ] apply przechodzi, w konsoli widać VPC z 4 subnetami i 2 tablicami
- [ ] destroy sprząta wszystko (konsola pusta)
- [ ] umiem odpowiedzieć na pytania kontrolne poniżej

### Pytania kontrolne (bank pytań rośnie z każdym zadaniem)
1. Po co `terraform.tfstate`, co jest w środku, czemu nie na GitHub?
2. `plan` vs `apply`; co się stanie przy apply bez zmian w kodzie?
3. Czemu prywatne subnety w oryginale miały NAT, a tu go nie ma?
4. Po co `outputs`?
5. `data` block vs `resource` block — różnica?
6. `module` vs surowe `resource`? Co jest w środku modułu VPC?
7. Czy kolejność zasobów w pliku ma znaczenie? (graf zależności)
8. Czemu przypinać wersje providera? Co znaczy `~> 5.92`?

---

## Koszty (pilnuj tego!)
- Zadanie 1 = 0 zł (VPC/subnety/IGW/route tables darmowe)
- **NIE free tier**: NAT Gateway (~$33/mies + dane), NLB/ALB (~$16/mies),
  Transit Gateway — pomijamy albo tworzymy na chwilę i od razu destroy
- Sprawdzić w Billing ile zostało free tieru (12 mies. od założenia konta)
- EC2 t3.micro i RDS db.t3.micro = 750h/mies w free tier

## Kolejne zadania (po zrobieniu 1)
- **2**: security groups + bastion EC2 (t3.micro, key pair, `data` AMI wraca)
- **3**: RDS MySQL (free tier) + db_subnet_group na prywatnych subnetach
- **4**: S3 + IAM role dla EC2 + alarm CloudWatch
- **5**: ALB + Auto Scaling Group + launch template (uwaga na koszty!)
- **6**: refaktor na moduły + remote state w S3

## TODO porządkowe
- [ ] `.gitignore` jest PUSTY — dopisać przed pierwszym pushem:
      `.terraform/`, `*.tfstate`, `*.tfstate.backup`, `.gitignore` na .swp
- [ ] usunąć śmieci: `main.tf.save`, `.main.tf.swp` (artefakty vima)
