# ============================================================================
# GreenLogistics - Script de lancement (Windows PowerShell)
# ============================================================================

# Parametres
$OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "GreenLogistics - Deploiement"

# Nom du cluster kind
$ClusterName = "greenlogistics-cluster"

function Print-Header {
    Clear-Host
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "             GreenLogistics - Systeme de Gestion and Deploiement      " -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host ""
}

function Check-Prerequisites {
    Write-Host "[*] Verification des prerequis..." -ForegroundColor Cyan
    $missing = 0

    # Verifier Docker
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $dockerCmd) {
        Write-Host "[X] Docker n'est pas installe." -ForegroundColor Red
        $missing++
    }
    else {
        # Verifier si Docker est demarre
        & docker info >$null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] Docker est installe mais n'est pas demarre. Veuillez demarrer Docker Desktop." -ForegroundColor Yellow
            $missing++
        }
        else {
            Write-Host "[V] Docker est installe et en cours d'execution." -ForegroundColor Green
        }
    }

    # Verifier Terraform
    $tfCmd = Get-Command terraform -ErrorAction SilentlyContinue
    if ($null -eq $tfCmd) {
        Write-Host "[X] Terraform n'est pas installe." -ForegroundColor Red
        $missing++
    }
    else {
        $tfVer = & terraform -v | Select-Object -First 1
        Write-Host "[V] Terraform est installe ($tfVer)." -ForegroundColor Green
    }

    # Verifier Helm
    $helmCmd = Get-Command helm -ErrorAction SilentlyContinue
    if ($null -eq $helmCmd) {
        Write-Host "[!] Helm n'est pas installe. Requis pour le mode Kubernetes." -ForegroundColor Yellow
    }
    else {
        Write-Host "[V] Helm est installe." -ForegroundColor Green
    }

    # Verifier kubectl
    $kubectlCmd = Get-Command kubectl -ErrorAction SilentlyContinue
    if ($null -eq $kubectlCmd) {
        Write-Host "[!] kubectl n'est pas installe. Requis pour interagir avec Kubernetes." -ForegroundColor Yellow
    }
    else {
        Write-Host "[V] kubectl est installe." -ForegroundColor Green
    }

    # Verifier kind
    $kindCmd = Get-Command kind -ErrorAction SilentlyContinue
    if ($null -eq $kindCmd) {
        Write-Host "[!] kind n'est pas installe. Requis pour creer le cluster Kubernetes local." -ForegroundColor Yellow
    }
    else {
        Write-Host "[V] kind est installe." -ForegroundColor Green
    }

    Write-Host ""
    if ($missing -gt 0) {
        Write-Host "[Attention] Certains prerequis sont manquants ou non demarres." -ForegroundColor Yellow
        Write-Host "Veuillez resoudre ces alertes avant de lancer un deploiement." -ForegroundColor Yellow
        Write-Host ""
    }
}

function Deploy-Kubernetes {
    Print-Header
    Write-Host "[*] Deploiement en Mode Kubernetes via Terraform..." -ForegroundColor Cyan

    # S'assurer que Docker tourne
    & docker info >$null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[Erreur] Le demon Docker n'est pas demarre. Impossible de creer le cluster." -ForegroundColor Red
        Read-Host "Appuyez sur Entree pour revenir au menu..."
        return
    }

    # Verifier si des conteneurs du cluster existent mais sont arretes
    $exitedContainers = & docker ps -a --filter "name=greenlogistics-cluster" --filter "status=exited" --format "{{.Names}}"
    if ($exitedContainers) {
        Write-Host "[!] Les conteneurs du cluster kind existent mais sont arretes (ex. apres un redemarrage du PC)." -ForegroundColor Yellow
        Write-Host "    Tentative de redemarrage automatique des conteneurs..." -ForegroundColor Cyan
        foreach ($container in $exitedContainers) {
            & docker start $container >$null
        }
        Write-Host "[V] Conteneurs redemarres avec succes." -ForegroundColor Green
        Start-Sleep -Seconds 2
    }

    # Creation des fichiers .env si non existants
    Write-Host "[*] Initialisation des fichiers .env des services si necessaire..." -ForegroundColor Cyan
    $services = @("delivery-service", "gps-ingest-service", "notification-service", "gps-simulator")
    foreach ($service in $services) {
        $envPath = "services/$service/.env"
        $examplePath = "services/$service/.env.example"
        if (!(Test-Path $envPath) -and (Test-Path $examplePath)) {
            Copy-Item $examplePath $envPath
            Write-Host "    -> Cree $envPath" -ForegroundColor Gray
        }
    }

    # Lancement de Terraform
    Write-Host "[*] Execution de Terraform..." -ForegroundColor Cyan
    Push-Location terraform
    try {
        Write-Host "    -> Initialisation de Terraform..." -ForegroundColor Gray
        & terraform init
        Write-Host "    -> Application du plan Terraform (cela peut prendre plusieurs minutes)..." -ForegroundColor Gray
        & terraform apply -auto-approve
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "[V] Deploiement Terraform termine avec succes !" -ForegroundColor Green
            Write-Host ""
            Write-Host "Prochaines etapes recommandees :" -ForegroundColor Yellow
            Write-Host "1. Attendez 2-3 minutes pour que tous les Pods soient prets ('kubectl get pods -A')"
            Write-Host "2. Lancez l'option [3] du menu de ce script pour activer les acces locaux (Port-Forwarding)" -ForegroundColor Yellow
        }
        else {
            Write-Host "[X] Une erreur est survenue lors de l'application de Terraform." -ForegroundColor Red
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ""
    Read-Host "Appuyez sur Entree pour revenir au menu..."
}

function Deploy-DockerCompose {
    Print-Header
    Write-Host "[*] Deploiement en Mode Docker Compose..." -ForegroundColor Cyan

    # S'assurer que Docker tourne
    & docker info >$null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[Erreur] Le demon Docker n'est pas demarre. Impossible de lancer Docker Compose." -ForegroundColor Red
        Read-Host "Appuyez sur Entree pour revenir au menu..."
        return
    }

    & docker compose up -d
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[V] Tous les conteneurs ont ete lances en arriere-plan !" -ForegroundColor Green
        Write-Host ""
        Write-Host "Acces aux applications :" -ForegroundColor Green
        Write-Host "  - Carte temps reel (Delivery Service) : http://localhost:3000"
        Write-Host "  - API d'ingestion GPS                 : http://localhost:3001"
        Write-Host "  - Console Redpanda (Broker Kafka)     : http://localhost:8080"
        Write-Host "  - Simulateur GPS                      : http://localhost:3003"
        Write-Host "  - MailHog (Serveur Mail Simule)       : http://localhost:8025"
    }
    else {
        Write-Host "[X] Une erreur est survenue lors du demarrage de Docker Compose." -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Appuyez sur Entree pour revenir au menu..."
}

function Start-PortForward {
    Print-Header
    Write-Host "[*] Configuration du Port-Forwarding Kubernetes..." -ForegroundColor Cyan

    # Verification du contexte
    $context = & kubectl config current-context 2>$null
    if ($context -notlike "*kind-$ClusterName*") {
        Write-Host "[!] Le contexte kubectl actuel ($context) ne semble pas correspondre a 'kind-$ClusterName'." -ForegroundColor Yellow
        $ans = Read-Host "Voulez-vous quand meme tenter le port-forwarding ? (y/n)"
        if ($ans -notmatch "^[Yy]$") {
            return
        }
    }

    # Fermer les redirections existantes
    Write-Host "[*] Arret des redirections de ports existantes..." -ForegroundColor Cyan
    Get-CimInstance Win32_Process -Filter "name = 'kubectl.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*port-forward*"
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1

    Write-Host "[*] Lancement des redirections en arriere-plan..." -ForegroundColor Cyan

    # Lancement des processus de port-forwarding masques
    Start-Process kubectl -ArgumentList "port-forward service/delivery-service -n app 8000:3000" -WindowStyle Hidden
    Start-Process kubectl -ArgumentList "port-forward service/argocd-server -n argocd 8080:443" -WindowStyle Hidden
    # Utilisation du port 3004 pour Grafana pour eviter le conflit avec delivery-service (3000)
    Start-Process kubectl -ArgumentList "port-forward service/kps-grafana -n monitoring 3004:80" -WindowStyle Hidden
    Start-Process kubectl -ArgumentList "port-forward service/mailhog -n mail 8025:8025" -WindowStyle Hidden
    Start-Process kubectl -ArgumentList "port-forward service/kubecost-cost-analyzer -n kubecost 9090:9090" -WindowStyle Hidden
    Start-Process kubectl -ArgumentList "port-forward deployment/gps-simulator -n app 3003:3003" -WindowStyle Hidden

    Start-Sleep -Seconds 2
    Write-Host "[V] Redirections lancees avec succes !" -ForegroundColor Green
    Write-Host ""
    Write-Host "Liens d'acces a vos applications Kubernetes :" -ForegroundColor Green
    Write-Host "  - Carte temps reel (Leaflet)     : http://localhost:8000" -ForegroundColor Blue
    Write-Host "  - ArgoCD Console Web (GitOps)     : https://localhost:8080" -ForegroundColor Blue
    Write-Host "  - Grafana (Monitoring and SLOs)     : http://localhost:3004" -ForegroundColor Blue
    Write-Host "  - MailHog (Simulateur d'e-mails)   : http://localhost:8025" -ForegroundColor Blue
    Write-Host "  - Kubecost (Analyse FinOps)       : http://localhost:9090" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Note : Les redirections tournent en tache de fond." -ForegroundColor Yellow
    Write-Host "Pour les arreter, relancez cette option ou nettoyez l'infrastructure." -ForegroundColor Yellow
    Write-Host ""

    Read-Host "Appuyez sur Entree pour revenir au menu..."
}

function Clean-Infrastructure {
    Print-Header
    Write-Host "[!] Procedure de nettoyage de l'infrastructure..." -ForegroundColor Yellow

    # Arret des redirections
    Write-Host " -> Arret des port-forwards..." -ForegroundColor Gray
    Get-CimInstance Win32_Process -Filter "name = 'kubectl.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*port-forward*"
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

    Write-Host " -> Que souhaitez-vous supprimer ?" -ForegroundColor Cyan
    Write-Host "    1. Cluster Kubernetes (kind) uniquement"
    Write-Host "    2. Environnement Docker Compose uniquement"
    Write-Host "    3. Tout nettoyer (K8s + Docker Compose + etats Terraform)"
    Write-Host "    4. Retour au menu"
    $cleanChoice = Read-Host "Votre choix"

    switch ($cleanChoice) {
        "1" {
            Write-Host "[*] Suppression du cluster kind..." -ForegroundColor Cyan
            & kind delete cluster --name $ClusterName
        }
        "2" {
            Write-Host "[*] Arret de Docker Compose..." -ForegroundColor Cyan
            & docker compose down -v
        }
        "3" {
            Write-Host "[*] Suppression du cluster kind..." -ForegroundColor Cyan
            & kind delete cluster --name $ClusterName
            Write-Host "[*] Arret de Docker Compose..." -ForegroundColor Cyan
            & docker compose down -v
            Write-Host "[*] Suppression des fichiers d'etat Terraform..." -ForegroundColor Cyan
            Remove-Item terraform/terraform.tfstate, terraform/terraform.tfstate.backup, terraform/plan.tfplan -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force terraform/.terraform -ErrorAction SilentlyContinue
            Write-Host "[V] Nettoyage complet effectuer !" -ForegroundColor Green
        }
        default {
            return
        }
    }

    Write-Host ""
    Read-Host "Appuyez sur Entree pour revenir au menu..."
}

# Boucle principale
while ($true) {
    Print-Header
    Check-Prerequisites

    Write-Host "Menu de deploiement :" -ForegroundColor Cyan
    Write-Host "  [1] Lancer le projet via Kubernetes & Terraform (Standard / Production)"
    Write-Host "  [2] Lancer le projet via Docker Compose (Leger / Developpement)"
    Write-Host "  [3] Activer les acces locaux / Port-Forwarding (Mode Kubernetes)"
    Write-Host "  [4] Nettoyer / Arrêter l'infrastructure"
    Write-Host "  [5] Quitter"
    Write-Host ""
    $choice = Read-Host "Veuillez choisir une option (1-5)"

    switch ($choice) {
        "1" { Deploy-Kubernetes }
        "2" { Deploy-DockerCompose }
        "3" { Start-PortForward }
        "4" { Clean-Infrastructure }
        "5" { 
            Write-Host "Au revoir !" -ForegroundColor Green
            exit 0
        }
        default {
            Write-Host "Option invalide." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
