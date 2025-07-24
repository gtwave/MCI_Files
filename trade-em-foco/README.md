# Trade em Foco - Website

Este é um site baseado no layout do Laatus.com.br, adaptado para a marca "Trade em Foco". O site foi desenvolvido utilizando HTML, CSS e JavaScript puros e está preparado para execução em container Docker.

## Estrutura do Projeto

```
trade-em-foco/
├── index.html          # Página principal
├── styles.css          # Estilos CSS
├── script.js           # JavaScript para interatividade
├── logo.svg            # Logo da Trade em Foco
├── avatar1.jpg         # Imagem de avatar 1
├── avatar2.jpg         # Imagem de avatar 2
├── avatar3.jpg         # Imagem de avatar 3
├── avatar4.jpg         # Imagem de avatar 4
├── Dockerfile          # Configuração do container Docker
├── nginx.conf          # Configuração do servidor Nginx
├── docker-compose.yml  # Orquestração com Docker Compose
├── .dockerignore       # Arquivos ignorados pelo Docker
└── README.md           # Este arquivo
```

## Características do Site

- **Design Responsivo**: Adaptável para desktop, tablet e mobile
- **Animações Suaves**: Efeitos de transição e animações CSS
- **Menu Mobile**: Hamburger menu para dispositivos móveis
- **Otimizado**: Código limpo e otimizado para performance
- **SEO Friendly**: Estrutura HTML semântica

## Como Executar

### Opção 1: Docker Compose (Recomendado)

```bash
# Navegar para o diretório do projeto
cd trade-em-foco

# Construir e executar o container
docker-compose up -d

# O site estará disponível em http://localhost:8080
```

### Opção 2: Docker Manual

```bash
# Construir a imagem
docker build -t trade-em-foco .

# Executar o container
docker run -d -p 8080:80 --name trade-em-foco-website trade-em-foco

# O site estará disponível em http://localhost:8080
```

### Opção 3: Servidor Local (Desenvolvimento)

```bash
# Usar um servidor HTTP simples (Python)
python3 -m http.server 8000

# Ou usar Node.js
npx http-server -p 8000

# O site estará disponível em http://localhost:8000
```

## Comandos Docker Úteis

```bash
# Parar o container
docker-compose down

# Ver logs
docker-compose logs -f

# Reconstruir após mudanças
docker-compose up --build -d

# Remover tudo
docker-compose down --volumes --rmi all
```

## Tecnologias Utilizadas

- **HTML5**: Estrutura semântica
- **CSS3**: Estilos modernos com Flexbox e Grid
- **JavaScript ES6+**: Funcionalidades interativas
- **Nginx**: Servidor web no container
- **Docker**: Containerização
- **Docker Compose**: Orquestração

## Funcionalidades

1. **Header Fixo**: Navegação sempre visível
2. **Hero Section**: Seção principal com call-to-action
3. **Metodologia**: Apresentação dos 3 passos
4. **Depoimentos**: Seção de cases de sucesso
5. **Conteúdo Gratuito**: Links para recursos
6. **Panorama**: Descrição dos serviços

## Customização

Para personalizar o site:

1. **Cores**: Edite as variáveis CSS no arquivo `styles.css`
2. **Conteúdo**: Modifique o texto no arquivo `index.html`
3. **Imagens**: Substitua os arquivos de imagem mantendo os mesmos nomes
4. **Logo**: Edite o arquivo `logo.svg` ou substitua por uma imagem

## Suporte

O site é compatível com:
- Chrome 60+
- Firefox 55+
- Safari 12+
- Edge 79+
- Dispositivos móveis iOS e Android

## Performance

- **Gzip**: Compressão habilitada
- **Cache**: Headers de cache otimizados
- **Minificação**: CSS e JS otimizados
- **Imagens**: Formato otimizado para web

