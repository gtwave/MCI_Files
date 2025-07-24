#!/bin/bash

# Script para executar o site Trade em Foco em container Docker

echo "=== Trade em Foco - Docker Setup ==="
echo ""

# Verificar se Docker está instalado
if ! command -v docker &> /dev/null; then
    echo "Docker não está instalado. Instalando..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    sudo systemctl start docker
    sudo systemctl enable docker
    echo "Docker instalado com sucesso!"
    echo "IMPORTANTE: Você pode precisar fazer logout/login para usar Docker sem sudo"
fi

# Parar container existente se estiver rodando
echo "Parando container existente (se houver)..."
sudo docker stop trade-em-foco-website 2>/dev/null || true
sudo docker rm trade-em-foco-website 2>/dev/null || true

# Construir a imagem
echo "Construindo imagem Docker..."
if sudo docker build -t trade-em-foco . --no-cache; then
    echo "Imagem construída com sucesso!"
else
    echo "Erro ao construir imagem Docker. Tentando método alternativo..."
    echo "Iniciando servidor HTTP Python..."
    
    # Matar processos Python existentes na porta 8080
    sudo pkill -f "python3 -m http.server 8080" 2>/dev/null || true
    
    # Iniciar servidor HTTP Python
    nohup python3 -m http.server 8080 > server.log 2>&1 &
    sleep 2
    
    if curl -s http://localhost:8080 > /dev/null; then
        echo "Servidor HTTP iniciado com sucesso!"
        echo "Site disponível em: http://localhost:8080"
        echo "Para parar o servidor: sudo pkill -f 'python3 -m http.server 8080'"
        exit 0
    else
        echo "Erro ao iniciar servidor HTTP"
        exit 1
    fi
fi

# Executar container
echo "Iniciando container..."
if sudo docker run -d -p 8080:80 --name trade-em-foco-website trade-em-foco; then
    echo ""
    echo "=== SUCESSO! ==="
    echo "Site Trade em Foco está rodando!"
    echo "Acesse: http://localhost:8080"
    echo ""
    echo "Comandos úteis:"
    echo "  Ver logs: sudo docker logs trade-em-foco-website"
    echo "  Parar: sudo docker stop trade-em-foco-website"
    echo "  Remover: sudo docker rm trade-em-foco-website"
    echo ""
else
    echo "Erro ao iniciar container. Tentando método alternativo..."
    echo "Iniciando servidor HTTP Python..."
    
    # Matar processos Python existentes na porta 8080
    sudo pkill -f "python3 -m http.server 8080" 2>/dev/null || true
    
    # Iniciar servidor HTTP Python
    nohup python3 -m http.server 8080 > server.log 2>&1 &
    sleep 2
    
    if curl -s http://localhost:8080 > /dev/null; then
        echo ""
        echo "=== SUCESSO (Método Alternativo)! ==="
        echo "Site Trade em Foco está rodando!"
        echo "Acesse: http://localhost:8080"
        echo "Para parar o servidor: sudo pkill -f 'python3 -m http.server 8080'"
    else
        echo "Erro ao iniciar servidor HTTP"
        exit 1
    fi
fi

