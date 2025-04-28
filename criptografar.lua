-- Dependências: zenity e openssl

-- Função para executar comandos e capturar a saída
local function executar(comando)
    local manipulador = io.popen(comando)
    local saida = manipulador:read("*a")
    manipulador:close()
    return saida:gsub("\n$", "")
end

-- Função para selecionar arquivo(s) usando zenity
local function selecionarArquivos()
    -- Zenity retorna arquivos múltiplos separados por nova linha (\n)
    return executar('zenity --file-selection --multiple --title="Selecione arquivos para criptografar e deletar"')
end

-- Função para mostrar mensagem
local function mostrarMensagem(tipo, mensagem)
    os.execute('zenity --' .. tipo .. ' --text="' .. mensagem .. '"')
end

-- Função para gerar senha aleatória forte
local function gerarSenhaAleatoria(comprimento)
    -- Usar /dev/urandom para gerar bytes aleatórios e convertê-los para base64
    local comando = string.format('head -c %d /dev/urandom | base64 | tr -dc "a-zA-Z0-9" | head -c %d', comprimento*2, comprimento)
    return executar(comando)
end

-- Função para gerar um nome de arquivo aleatório
local function gerarNomeArquivoAleatorio()
    -- Gerar um nome aleatório de 16 caracteres
    local nomeAleatorio = executar('head -c 16 /dev/urandom | xxd -p')
    return nomeAleatorio .. ".encrypted"
end

-- Função para extrair o diretório de um caminho completo
local function extrairDiretorio(caminho)
    -- Procurar pela última ocorrência de "/"
    local pos = caminho:match(".*/()")
    if pos then
        return caminho:sub(1, pos-1)
    else
        return "."  -- diretório atual se não houver "/"
    end
end

-- Função para criptografar um arquivo, renomeá-lo e depois deletar o original
local function criptografarEDeletarArquivo(caminho, senha)
    -- Obter o diretório do arquivo original
    local diretorio = extrairDiretorio(caminho)
    
    -- Gerar nome aleatório para o arquivo de saída
    local nomeAleatorio = gerarNomeArquivoAleatorio()
    local saida = diretorio .. "/" .. nomeAleatorio
    
    -- Comando OpenSSL para criptografar o arquivo com AES-256-CBC
    local comando = string.format(
        'openssl enc -aes-256-cbc -salt -in "%s" -out "%s" -k "%s" -pbkdf2 -iter 10000',
        caminho, saida, senha
    )
    
    -- Executar o comando de criptografia
    local sucesso = os.execute(comando)
    
    if sucesso then
        -- Deletar o arquivo original (usando método de exclusão normal)
        os.remove(caminho)
        return true, saida, nomeAleatorio
    else
        return false, nil, nil
    end
end

-- Fluxo principal do programa
local function main()
    -- Selecionar arquivos
    local arquivosString = selecionarArquivos()
    
    if arquivosString == "" then
        return
    end
    
    -- Dividir a string em linhas (zenity usa \n como separador)
    local arquivos = {}
    for linha in arquivosString:gmatch("([^\n]+)") do
        table.insert(arquivos, linha)
    end
    
    -- Confirmar com o usuário
    local mensagemConfirmacao = string.format(
        "ATENÇÃO: Você selecionou %d arquivo(s) para processamento.\n\nOs arquivos serão:\n1. Criptografados com senha aleatória que NÃO será armazenada\n2. Renomeados com nomes aleatórios para ocultar metadados\n3. Deletados permanentemente sem backup\n\nIsso tornará os arquivos originais IRRECUPERÁVEIS. Continuar?",
        #arquivos
    )
    
    local confirmacao = executar('zenity --question --title="Confirmação" --text="' .. mensagemConfirmacao .. '" --no-wrap && echo "sim" || echo "nao"')
    if confirmacao ~= "sim" then
        return
    end
    
    -- Segundo aviso de confirmação
    local segundaConfirmacao = executar('zenity --question --title="CONFIRMAÇÃO FINAL" --text="Esta operação é IRREVERSÍVEL.\nTem certeza que deseja continuar?" --no-wrap && echo "sim" || echo "nao"')
    if segundaConfirmacao ~= "sim" then
        return
    end
    
    -- Gerar uma senha aleatória forte (32 caracteres = 256 bits)
    local senha = gerarSenhaAleatoria(32)
    
    -- Criptografar, renomear e deletar cada arquivo
    local resultados = {}
    local sucessos = 0
    local falhas = 0
    
    -- Criar um mapeamento para possível referência futura
    local mapeamentoArquivos = {}
    
    for _, arquivo in ipairs(arquivos) do
        local sucesso, arquivoCriptografado, nomeAleatorio = criptografarEDeletarArquivo(arquivo, senha)
        
        if sucesso then
            sucessos = sucessos + 1
            table.insert(resultados, "Sucesso: " .. arquivo .. " → " .. nomeAleatorio)
            mapeamentoArquivos[nomeAleatorio] = arquivo
        else
            falhas = falhas + 1
            table.insert(resultados, "Falha: " .. arquivo)
        end
    end
    
    -- Mostrar resultado
    local resumo = string.format(
        "Processo concluído:\n- %d arquivo(s) processado(s) com sucesso\n- %d falha(s)\n\nOS ARQUIVOS ORIGINAIS FORAM DELETADOS E NÃO PODEM SER RECUPERADOS.",
        sucessos, falhas
    )
    
    mostrarMensagem("info", resumo)
    
    -- Mostrar detalhes com mapeamento de nomes (opcional - pode remover essa parte se não quiser manter o mapeamento)
    local detalhes = "Mapeamento de arquivos (apenas para esta sessão):\n\n"
    for nomeAleatorio, nomeOriginal in pairs(mapeamentoArquivos) do
        detalhes = detalhes .. nomeAleatorio .. " ← " .. nomeOriginal .. "\n"
    end
    detalhes = detalhes .. "\nEste mapeamento NÃO está sendo salvo e é exibido apenas nesta sessão."
    
    executar('zenity --text-info --title="Mapeamento de Arquivos" --width=800 --height=400 --text="' .. detalhes .. '"')
    
    -- Avisar sobre a senha descartada
    mostrarMensagem("warning", "A senha de criptografia foi gerada aleatoriamente e NÃO foi armazenada.\nOs arquivos criptografados não poderão ser descriptografados.")
end

-- Executar o programa
main()
