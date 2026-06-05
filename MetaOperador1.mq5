//+------------------------------------------------------------------------+
//|                                                MetaOperador1.mq5       |
//|                                  Copyright 2026, MetaQuotes Ltd.       |
//|                                             https://www.mql5.com       |
//|   Robo de execucao automatizada de ordens (Expert Advisor)             |
//|                                                                        |
//|   Padrao: codigo orientado a funcoes + Clean Code + SOLID              |
//|   (cada funcao com responsabilidade unica, isolada e testavel)         |
//|                                                                        |
//|                                                                        |
//|   ESTE CODIGO NAO E RECOMENDACAO FINANCEIRA. Faca backtest no          |
//|   Strategy Tester antes de utilizar em conta real.                     |
//+------------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.tradeemfoco.com.br"
#property version   "1.00"
#property strict


#include <Trade/Trade.mqh>   // Biblioteca padrao de execucao de ordens

//==================================================================//
//  SECAO 1 - CONSTANTES / "TIPOS"                                   //
//==================================================================//

#define RSI_PERIODO        14   // Periodo do indicador RSI
#define EMA_RAPIDA         20   // Media movel exponencial rapida
#define EMA_MEDIA          50   // Media movel exponencial intermediaria
#define EMA_LENTA          72   // Media movel exponencial lenta
#define LOOKBACK_LIQUIDEZ  30   // Qtd. de candles analisados na limpeza de liquidez

// Enumeracao auxiliar para deixar a direcao da operacao explicita e tipada.
enum ENUM_DIRECAO
{
   DIRECAO_COMPRA = 1,   // Operacao de compra (long)
   DIRECAO_VENDA  = -1   // Operacao de venda (short)
};

//==================================================================//
//  SECAO 2 - PARAMETROS DE ENTRADA E SAIDA                          //
//==================================================================//

input double   StopOperacao        = 100.0;     // Perda financeira maxima por operacao (em dinheiro)
input int      MagicId             = 123456;    // ID (Magic) para rastrear as ordens deste robo
input string   CodigoAtivo         = "XAUUSD";   // Ativo analisado/operado pelo robo
input double   GainOperacao        = 200.0;     // Ganho financeiro maximo por operacao (0 = desativado)
input double   Alavancagem         = 0.1;       // Volume por ordem (contratos/lotes): 0.01 ate 10
input int      MaxOperacoesDia     = 10;        // Qtd. maxima de operacoes no dia (0 = sem limite)
input double   MaxStopDia          = 500.0;     // Perda maxima acumulada no dia (modulo; 0 = sem limite)
input double   MaxMetaDia          = 1000.0;    // Meta de resultado no dia (0 = sem limite)
input datetime HoraInicioExecucao  = 0;         // Horario de inicio (0 = sem restricao de inicio)
input datetime HoraFimExecucao     = 0;         // Horario de fim    (0 = sem restricao de fim)
input int      Risco               = 2;         //#TODO: mudar nome da variavel Coeficiente de risco para ABRIR operacao
input int      Risco_Fechamento    = 0;         // Coeficiente de risco para FECHAR operacao
input double   Trail_stop          = 50.0;      // Distancia do stop movel (em pontos do ativo)
input bool     ValidationMode = true;  //Quando essa valor for positivo executa o Robot em modo de teste para validar cada regra separada
input int      ValidationNumber = 4;   //Numero Sequencial da condicao que sera validada durante o teste'
//input double   TempoGrafico        = M3

//==================================================================//
//  SECAO 3 - VARIAVEIS INTERNAS / ESTADO GLOBAL                     //
//==================================================================//

double   ResultadoTotalDia = 0.0;   // Resultado financeiro acumulado do dia
double   CountOperacoesDia = 0.0;   // Quantidade de operacoes abertas no dia

CTrade   g_trade;                   // Objeto de execucao de ordens (biblioteca padrao)
datetime g_tempoUltimaBarra = 0;    // Tempo da ultima barra (para detectar candle fechado)
int      g_vAnalise         = 0;    // Ultimo v_Analise calculado no fechamento do candle
                                    // (usado no gerenciamento da posicao tick a tick)

// Handles dos indicadores (devem ser liberados em OnDeinit)
int      g_handleRSI   = INVALID_HANDLE;
int      g_handleEMA20 = INVALID_HANDLE;
int      g_handleEMA50 = INVALID_HANDLE;
int      g_handleEMA72 = INVALID_HANDLE;

double RSI_hist = 0;

//==================================================================//
//  SECAO 4 - FUNCAO PRINCIPAL (executada a cada candle fechado)     //
//  Conforme solicitado, e a primeira funcao apos as declaracoes.    //
//==================================================================//

//+------------------------------------------------------------------+
//| ExecutarEstrategia                                               |
//| Responsabilidade: recalcular v_Analise e avaliar a ABERTURA de   |
//| novas operacoes. Disparada APENAS no fechamento de candle, pois  |
//| os sinais (RSI, EMAs, SMC) so mudam quando a barra fecha.        |
//| O gerenciamento da posicao aberta acontece tick a tick (OnTick). |
//+------------------------------------------------------------------+
void ExecutarEstrategia()
{
   if(ValidationMode)
     {
     int aux = 0;
      switch(ValidationNumber)
        {
         case  1: //#01 = PivotRSI()
           aux = PivotRSI();
           break;
         case  2:
           aux = LimpezaLiquidez();
           break;
         case  3:
            aux = Tendencia();
           break;
         case  4:
            aux = RSI_Divergence(CodigoAtivo, PERIOD_M3);
           break;
         case  5:
            aux = RSI_Institutional_Confluence(CodigoAtivo,PERIOD_H3);
           break; 
           
         default:
           break;
        }
        
       if(aux > 0)
         {
          AbrirOperacao(DIRECAO_COMPRA);
          //AbrirOperacao(DIRECAO_VENDA);
          Print("[Execucao em modo de validacao] Operacao de Compra - ValidationNumber", ValidationNumber, " | Magic=", MagicId);
         }
         
       if(aux < 0)
         {
          AbrirOperacao(DIRECAO_VENDA);
          //AbrirOperacao(DIRECAO_COMPRA);
          Print("[Execucao em modo de validacao] Operacao de Compra - ValidationNumber", ValidationNumber, " | Magic=", MagicId);
         }
     }
   // Recalcula o sinal e guarda em g_vAnalise para uso tick a tick.
   g_vAnalise = CalcularVAnalise();

   // Atualiza o resultado financeiro e a contagem de operacoes do dia.
   AtualizarEstatisticasDia();

   // Com posicao aberta nao abrimos nova ordem (uma posicao por vez).
   // O gerenciamento dela ja ocorre a cada tick em OnTick.
   if(TemPosicao())
      return;

   // ---- Sem posicao aberta: avaliar se pode abrir nova operacao ----
   if(!DentroDoHorario())
      return; // Fora da janela de execucao configurada.

   if(LimiteOperacoesDiaAtingido())
   {
      Print("[ROBO] Limite de operacoes do dia atingido. Nenhuma nova ordem.");
      return;
   }
   if(LimiteStopDiaAtingido())
   {
      Print("[ROBO] Stop diario atingido. Nenhuma nova ordem.");
      return;
   }
   if(LimiteMetaDiaAtingido())
   {
      Print("[ROBO] Meta diaria atingida. Nenhuma nova ordem.");
      return;
   }
   
   

   // Decisao de entrada com base no alinhamento das analises:
   //   v_Analise >= Risco          -> compra
   //   v_Analise <= (Risco * -1)    -> venda
   
   if(!ValidationMode)
     {
         if(g_vAnalise >= Risco)
            AbrirOperacao(DIRECAO_COMPRA);
         else if(g_vAnalise <= (Risco * -1))
            AbrirOperacao(DIRECAO_VENDA);
     }

}

//+------------------------------------------------------------------+
//| CalcularVAnalise                                                 |
//| Responsabilidade: somar as 4 analises de contexto e retornar o   |
//| score v_Analise. Sempre reinicia em 0 a cada chamada.            |
//+------------------------------------------------------------------+
int CalcularVAnalise()
{
   int v_Analise = 0;                 // Reinicia em 0 a cada execucao.
   v_Analise += PivotRSI();           // Sobrecompra / sobrevenda
   v_Analise += LimpezaLiquidez();    // Falso rompimento (SMC)
   v_Analise += Tendencia();          // Alinhamento das medias moveis
   v_Analise += Continuidade();       // Continuidade do movimento
   //v_Analise += MetododoVitor();
   return v_Analise;
}


//==================================================================//
//  SECAO 9 - EVENT HANDLERS / INICIALIZACAO DO SISTEMA              //
//  (equivalente ao registro e remocao de "listeners")              //
//==================================================================//
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//| OnInit - inicializa o robo e registra os indicadores             |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Configura o objeto de execucao de ordens.
   g_trade.SetExpertMagicNumber(MagicId);
   g_trade.SetTypeFillingBySymbol(CodigoAtivo);
   g_trade.SetDeviationInPoints(10);

   // Cria os handles dos indicadores (serao liberados em OnDeinit).
   g_handleRSI   = iRSI(CodigoAtivo, PERIOD_CURRENT, RSI_PERIODO, PRICE_CLOSE);
   g_handleEMA20 = iMA(CodigoAtivo, PERIOD_CURRENT, EMA_RAPIDA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleEMA50 = iMA(CodigoAtivo, PERIOD_CURRENT, EMA_MEDIA,  0, MODE_EMA, PRICE_CLOSE);
   g_handleEMA72 = iMA(CodigoAtivo, PERIOD_CURRENT, EMA_LENTA,  0, MODE_EMA, PRICE_CLOSE);

   if(g_handleRSI   == INVALID_HANDLE ||
      g_handleEMA20 == INVALID_HANDLE ||
      g_handleEMA50 == INVALID_HANDLE ||
      g_handleEMA72 == INVALID_HANDLE)
   {
      Print("[OnInit] Falha ao criar handles de indicadores. Codigo: ", GetLastError());
      return INIT_FAILED;
   }

   g_tempoUltimaBarra = iTime(CodigoAtivo, PERIOD_CURRENT, 0);

   Print("[OnInit] Robo inicializado para o ativo ", CodigoAtivo, " | Magic=", MagicId);
   return INIT_SUCCEEDED;
  }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//| OnDeinit - libera os handles (evita vazamento de recursos)       |
//| Equivalente a "remover os listeners" para nao deixar memory leak.|
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  
   if(g_handleRSI   != INVALID_HANDLE) IndicatorRelease(g_handleRSI);
   if(g_handleEMA20 != INVALID_HANDLE) IndicatorRelease(g_handleEMA20);
   if(g_handleEMA50 != INVALID_HANDLE) IndicatorRelease(g_handleEMA50);
   if(g_handleEMA72 != INVALID_HANDLE) IndicatorRelease(g_handleEMA72);

   g_handleRSI = g_handleEMA20 = g_handleEMA50 = g_handleEMA72 = INVALID_HANDLE;

   Print("[OnDeinit] Robo finalizado. Motivo: ", reason);   
  }
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//| - No fechamento do candle: recalcula o sinal e avalia entradas.  |
//| - A CADA TICK: gerencia a posicao aberta (trailing stop, stop e  |
//|   gain financeiro, fechamento por enfraquecimento do sinal).     |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1) Recalcula sinais e avalia ABERTURA somente quando a barra fecha.
   if(NovaBarra())
      ExecutarEstrategia();

   // 2) Protege/gerencia a posicao aberta em TODO tick (reage ao preco atual).
   if(TemPosicao())
      GerenciarPosicaoAberta(g_vAnalise);
      //GerenciarPosicaoAbertaporValor(g_vAnalise);
      //GerenciarPosicaoAbertaporPontos(g_vAnalise);
   
  }
//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int32_t id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
//---
   
  }
//+------------------------------------------------------------------+
//==================================================================//
//  SECAO 5 - FUNCOES DE ANALISE (retornam int: -1, 0 ou +1)         //
//==================================================================//

//+------------------------------------------------------------------+
//| PivotRSI  #01 - Test ValidationNumber = 1                                                       |
//| Retorna: int (-1 sobrecomprado/venda, +1 sobrevendido/compra, 0) |
//| Responsabilidade: medir sobrecompra/sobrevenda via RSI.          |
//+------------------------------------------------------------------+
int PivotRSI()
{
   // Precisamos apenas das últimas 3 barras fechadas para avaliar o cruzamento direto
   double bufferRSI[];
   ArraySetAsSeries(bufferRSI, true); // Índice [0] é o candle fechado mais recente
   
   // Lendo as últimas 3 barras fechadas (deslocamento 1 até 3)
   if(CopyBuffer(g_handleRSI, 0, 1, 3, bufferRSI) < 3)
   {
      Print("[PivotRSI] Erro ao ler o buffer do RSI. Codigo: ", GetLastError());
      return 0;
   }

   double nivelSobrecompra  = 70.0;
   double nivelSobrevenda   = 30.0;

   // -------------------------------------------------------------------------
   // LÓGICA DE RETORNO DA SOBRECOMPRA (Sinal de Venda)
   // -------------------------------------------------------------------------
   // Ponto 1: O candle anterior (ou o anterior a ele) estava acima de 70 (Sobrecomprado)
   bool esteve_sobrecomprado = (bufferRSI[1] > nivelSobrecompra || bufferRSI[2] > nivelSobrecompra);
   
   // Ponto 2: O candle atual [0] fechou CONFIRMANDO o cruzamento para baixo de 70
   bool cruzou_para_baixo = (bufferRSI[0] <= nivelSobrecompra);

   if(esteve_sobrecomprado && cruzou_para_baixo)
   {
      return -1; // Cruzou de volta para dentro: Sinal de Venda
   }

   // -------------------------------------------------------------------------
   // LÓGICA DE RETORNO DA SOBREVENDA (Sinal de Compra)
   // -------------------------------------------------------------------------
   // Ponto 1: O candle anterior (ou o anterior a ele) estava abaixo de 30 (Sobrevendido)
   bool esteve_sobrevendido = (bufferRSI[1] < nivelSobrevenda || bufferRSI[2] < nivelSobrevenda);
   
   // Ponto 2: O candle atual [0] fechou CONFIRMANDO o cruzamento para cima de 30
   bool cruzou_para_cima = (bufferRSI[0] >= nivelSobrevenda);

   if(esteve_sobrevendido && cruzou_para_cima)
   {
      return 1; // Cruzou de volta para dentro: Sinal de Compra
   }

   return 0; // Faixa neutra / Sem cruzamento confirmado neste candle
}

// Retorna: 1 para Divergência de Alta (Compra), -1 para Divergência de Baixa (Venda), 0 para Neutro
int RSI_Divergence(string symbol, ENUM_TIMEFRAMES timeframe)
{
    double rsi[];
    MqlRates rates[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(rates, true);

    // Precisamos de histórico suficiente (ex: 15 barras) para mapear dois topos/fundos passados
    if(CopyBuffer(g_handleRSI, 0, 1, 15, rsi) < 15) return 0;
    if(CopyRates(symbol, timeframe, 1, 15, rates) < 15) return 0;

    // --- IDENTIFICAÇÃO DE TOPOS E FUNDOS NO RSI ---
    // Encontra o pico mais recente (Pico A) e o anterior (Pico B)
    int picoA = -1, picoB = -1;
    int fundoA = -1, fundoB = -1;

    for(int i = 1; i < 14; i++)
    {
        // Identifica Topos (Picos) no RSI
        if(rsi[i] > rsi[i-1] && rsi[i] > rsi[i+1] && rsi[i] > 55.0)
        {
            if(picoA == -1) picoA = i;
            else if(picoB == -1) { picoB = i; break; }
        }
        // Identifica Fundos no RSI
        if(rsi[i] < rsi[i-1] && rsi[i] < rsi[i+1] && rsi[i] < 45.0)
        {
            if(fundoA == -1) fundoA = i;
            else if(fundoB == -1) { fundoB = i; break; }
        }
    }

    // --- VALIDAÇÃO DA DIVERGÊNCIA DE BAIXA (VENDA) ---
    if(picoA != -1 && picoB != -1)
    {
        // Preço fez Topo Mais Alto, mas RSI fez Topo Mais Baixo (Divergência Ursina)
        if(rates[picoA].high > rates[picoB].high && rsi[picoA] < rsi[picoB])
        {
            // Gatilho: O RSI atual [0] começou a apontar para baixo
            if(rsi[0] < rsi[1]) return -1;
        }
    }

    // --- VALIDAÇÃO DA DIVERGÊNCIA DE ALTA (COMPRA) ---
    if(fundoA != -1 && fundoB != -1)
    {
        // Preço fez Fundo Mais Baixo, mas RSI fez Fundo Mais Alto (Divergência Touro)
        if(rates[fundoA].low < rates[fundoB].low && rsi[fundoA] > rsi[fundoB])
        {
            // Gatilho: O RSI atual [0] começou a apontar para cima
            if(rsi[0] > rsi[1]) return 1;
        }
    }

    return 0;
}

// Retorna: 1 se o RSI virar dentro de uma zona institucional de alta, -1 para zona de baixa, 0 para neutro
int RSI_Institutional_Confluence(string symbol, ENUM_TIMEFRAMES timeframe)
{
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    // Leitura rápida do RSI (últimas 3 barras fechadas)
    if(CopyBuffer(g_handleRSI, 0, 1, 3, rsi) < 3) return 0;
    
    double nivelSobrecompra = 70.0;
    double nivelSobrevenda  = 30.0;
    
    // 1. CHAMA AS FUNÇÕES ANTERIORES DE SMC PARA CONTEXTO
    int liquidezSMC = CheckLiquiditySweep(symbol);
    int fvgSMC      = CheckFairValueGap(symbol, timeframe);
    
    // 2. AVALIAÇÃO DO GATILHO DE COMPRA CONFLUENTE
    // O RSI veio da sobrevenda...
    bool rsi_retornando_da_sobrevenda = (rsi[1] < nivelSobrevenda || rsi[2] < nivelSobrevenda) && (rsi[0] >= nivelSobrevenda);
    
    if(rsi_retornando_da_sobrevenda)
    {
        // ...Mas só valida se o preço acabou de capturar liquidez de fundo OU está mitigando um FVG de Alta
        if(liquidezSMC == 1 || fvgSMC == 1)
        {
            return 1; // Compra de Alta Probabilidade (Institucional + Varejo Exausto)
        }
    }
    
    // 3. AVALIAÇÃO DO GATILHO DE VENDA CONFLUENTE
    // O RSI veio da sobrecompra...
    bool rsi_retornando_da_sobrecompra = (rsi[1] > nivelSobrecompra || rsi[2] > nivelSobrecompra) && (rsi[0] <= nivelSobrecompra);
    
    if(rsi_retornando_da_sobrecompra)
    {
        // ...Mas só valida se o preço acabou de capturar liquidez de topo OU está mitigando um FVG de Baixa
        if(liquidezSMC == -1 || fvgSMC == -1)
        {
            return -1; // Venda de Alta Probabilidade
        }
    }
    
    return 0;
}

//+------------------------------------------------------------------+
//| LimpezaLiquidez                                                  |
//| Retorna: int (-1 varredura de topo/venda, +1 fundo/compra, 0)    |
//| Responsabilidade: detectar falso rompimento (limpeza de          |
//| liquidez) segundo o conceito de SMC. Heuristica simplificada:    |
//| a ultima candle fechada fura um topo/fundo anterior mas fecha    |
//| de volta, caracterizando o falso rompimento.                     |
//+------------------------------------------------------------------+
int LimpezaLiquidez()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   // Copia candles ja FECHADOS (a partir do deslocamento 1).
   if(CopyRates(CodigoAtivo, PERIOD_CURRENT, 1, LOOKBACK_LIQUIDEZ, rates) < LOOKBACK_LIQUIDEZ)
   {
      Print("[LimpezaLiquidez] Erro ao copiar candles. Codigo: ", GetLastError());
      return 0;
   }

   // rates[0] = ultima candle fechada. Topo/fundo de referencia ignora as 2 mais recentes.
   double topoAnterior  = rates[3].high;
   double fundoAnterior  = rates[3].low;
   for(int i = 3; i < LOOKBACK_LIQUIDEZ; i++)
   {
      if(rates[i].high > topoAnterior)  topoAnterior  = rates[i].high;
      if(rates[i].low  < fundoAnterior) fundoAnterior = rates[i].low;
   }

   // Varredura de TOPO: furou o topo anterior mas fechou abaixo dele -> venda
   if(rates[0].high > topoAnterior && rates[0].close < topoAnterior)
      return -1;

   // Varredura de FUNDO: furou o fundo anterior mas fechou acima dele -> compra
   if(rates[0].low < fundoAnterior && rates[0].close > fundoAnterior)
      return 1;

   return 0; // Nenhuma limpeza de liquidez identificada.
}

//+------------------------------------------------------------------+
//| Tendencia                                                        |
//| Retorna: int (+1 alta, -1 baixa, 0 indefinida)                   |
//| Responsabilidade: identificar a tendencia principal pelo         |
//| alinhamento das EMAs de 20, 50 e 72 periodos.                    |
//+------------------------------------------------------------------+
int Tendencia()
{
   double ema20[], ema50[], ema72[];

   // Le o valor de cada media no ultimo candle FECHADO (deslocamento 1).
   if(CopyBuffer(g_handleEMA20, 0, 1, 1, ema20) < 1 ||
      CopyBuffer(g_handleEMA50, 0, 1, 1, ema50) < 1 ||
      CopyBuffer(g_handleEMA72, 0, 1, 1, ema72) < 1)
   {
      Print("[Tendencia] Erro ao ler as medias moveis. Codigo: ", GetLastError());
      return 0;
   }

   double m20 = ema20[0];
   double m50 = ema50[0];
   double m72 = ema72[0];

   // Alinhamento crescente -> tendencia de alta -> compra
   if(m20 >= m50 && m50 >= m72) return 1;

   // Alinhamento decrescente -> tendencia de baixa -> venda
   if(m20 <= m50 && m50 <= m72) return -1;

   return 0; // Medias sem alinhamento claro.
}

//+------------------------------------------------------------------+
//| Continuidade                                                     |
//| Retorna: int (+1 continuidade de alta, -1 de baixa, 0)           |
//| Responsabilidade: medir a continuidade do movimento de preco.    |
//| OBS: o enunciado nao detalhou esta funcao. Implementacao         |
//| assumida: duas ultimas candles fechadas no mesmo sentido e com   |
//| fechamentos progressivos confirmam continuidade.                 |
//+------------------------------------------------------------------+
int Continuidade()
{
//   MqlRates rates[];
//   ArraySetAsSeries(rates, true);
//
//   if(CopyRates(CodigoAtivo, PERIOD_CURRENT, 1, 2, rates) < 2)
//   {
//      Print("[Continuidade] Erro ao copiar candles. Codigo: ", GetLastError());
//      return 0;
//   }
//
//   bool altaRecente   = rates[0].close > rates[0].open;
//   bool altaAnterior  = rates[1].close > rates[1].open;
//
//   // Duas candles de alta com fechamento crescente -> continuidade de alta
//   if(altaRecente && altaAnterior && rates[0].close > rates[1].close)
//      return 1;
//
//   // Duas candles de baixa com fechamento decrescente -> continuidade de baixa
//   if(!altaRecente && !altaAnterior && rates[0].close < rates[1].close)
//      return -1;

   return 0;
}
// Função Principal que consolida a matriz de decisão
int EvaluateSMCStrategy()
{
    string symbol = _Symbol;
    
    // 1. Valida o Viés Macro (H4)
    int macroBias = CheckMacroStructure(symbol, PERIOD_H4);
    if(macroBias == 0) return 0; // Sem direção clara no macro, não opera
    
    // 2. Valida se houve varredura de Liquidez (D1/M5)
    int liquiditySweep = CheckLiquiditySweep(symbol);
    if(liquiditySweep == 0) return 0; // Sem captura de liquidez, sem trade institucional
    
    // 3. Confirma a reversão pelo Micro CHoCH (M5)
    int microChoch = CheckMicroCHoCH(symbol, PERIOD_M5);
    
    // 4. Identifica a mitigação na Ineficiência/FVG (M5)
    int fvgStatus = CheckFairValueGap(symbol, PERIOD_M5);
    
    // CONFLUÊNCIA DE COMPRA
    // Viés de Alta E Liquidez Capturada no Fundo E Confirmação Micro de Alta
    if(macroBias == 1 && liquiditySweep == 1 && microChoch == 1 && fvgStatus == 1)
    {
        return 1; 
    }
    
    // CONFLUÊNCIA DE VENDA
    // Viés de Baixa E Liquidez Capturada no Topo E Confirmação Micro de Baixa
    if(macroBias == -1 && liquiditySweep == -1 && microChoch == -1 && fvgStatus == -1)
    {
        return -1;
    }
    
    return 0; // Neutro se qualquer um dos passos falhar na confluência
}

// Retorna: 1 se existe um FVG de Alta ativo, -1 se existe um FVG de Baixa ativo
int CheckFairValueGap(string symbol, ENUM_TIMEFRAMES timeframe)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    
    // Analisa o padrão de 3 candles consecutivos
    if(CopyRates(symbol, timeframe, 0, 4, rates) < 4) return 0;
    
    // FVG de Alta: A mínima do Candle 1 é maior que a máxima do Candle 3
    if(rates[1].low > rates[3].high)
    {
        // Se o preço atual (Candle 0) estiver testando essa região de gap
        if(rates[0].low <= rates[1].low && rates[0].close >= rates[3].high)
        {
            return 1; // Região de FVG de alta validada para entrada
        }
    }
    
    // FVG de Baixa: A máxima do Candle 1 é menor que a mínima do Candle 3
    if(rates[1].high < rates[3].low)
    {
        // Se o preço atual (Candle 0) estiver testando essa região de gap
        if(rates[0].high >= rates[1].high && rates[0].close <= rates[3].low)
        {
            return -1; // Região de FVG de baixa validada para entrada
        }
    }
    
    return 0;
}

// Retorna: 1 para CHoCH de Alta, -1 para CHoCH de Baixa, 0 para Neutro
int CheckMicroCHoCH(string symbol, ENUM_TIMEFRAMES timeframe)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    
    // Copia candles recentes do micro timeframe (ex: M1 ou M5)
    if(CopyRates(symbol, timeframe, 0, 10, rates) < 10) return 0;
    
    // Detecta CHoCH de Alta: Rompimento do último topo de uma micro tendência de baixa
    double microTopo = MathMax(rates[2].high, rates[3].high);
    if(rates[1].close > microTopo && rates[3].close < rates[4].close)
    {
        return 1; // Mudança de caráter para alta
    }
    
    // Detecta CHoCH de Baixa: Rompimento do último fundo de uma micro tendência de alta
    double microFundo = MathMin(rates[2].low, rates[3].low);
    if(rates[1].close < microFundo && rates[3].close > rates[4].close)
    {
        return -1; // Mudança de caráter para baixa
    }
    
    return 0;
}

// Retorna: 1 se capturou liquidez de venda (Pronto para COMPRA), -1 se capturou liquidez de compra (Pronto para VENDA)
int CheckLiquiditySweep(string symbol)
{
    MqlRates dailyRates[];
    MqlRates currentRates[];
    ArraySetAsSeries(dailyRates, true);
    ArraySetAsSeries(currentRates, true);
    
    // Obtém o candle diário anterior [1] e o candle atual do M5 [0]
    if(CopyRates(symbol, PERIOD_D1, 1, 1, dailyRates) < 1) return 0;
    if(CopyRates(symbol, PERIOD_M5, 0, 1, currentRates) < 1) return 0;
    
    double previousDayHigh = dailyRates[0].high;
    double previousDayLow  = dailyRates[0].low;
    
    // Varredura de Alta: Preço subiu acima da máxima diária e fechou abaixo dela
    if(currentRates[0].high > previousDayHigh && currentRates[0].close < previousDayHigh)
    {
        return -1; // Liquidez capturada no topo -> Possível Venda
    }
    
    // Varredura de Baixa: Preço desceu abaixo da mínima diária e fechou acima dela
    if(currentRates[0].low < previousDayLow && currentRates[0].close > previousDayLow)
    {
        return 1;  // Liquidez capturada no fundo -> Possível Compra
    }
    
    return 0;
}

// Retorna: 1 para Tendência de Alta, -1 para Baixa, 0 para Lateral
int CheckMacroStructure(string symbol, ENUM_TIMEFRAMES timeframe)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    
    // Copia as últimas 5 barras do timeframe macro (ex: H4)
    if(CopyRates(symbol, timeframe, 0, 5, rates) < 5) return 0;
    
    // Lógica simplificada de Direção: Topos e Fundos Ascendentes/Descendentes
    bool highers = (rates[1].high > rates[2].high) && (rates[2].high > rates[3].high);
    bool lowers  = (rates[1].low < rates[2].low) && (rates[2].low < rates[3].low);
    
    if(highers && rates[1].close > rates[2].high) return 1;  // Estrutura de Alta (BMS)
    if(lowers  && rates[1].close < rates[2].low)  return -1; // Estrutura de Baixa (BMS)
    
    return 0;
}
//==================================================================//
//  SECAO 6 - GERENCIAMENTO DA POSICAO ABERTA                        //
//==================================================================//

//+------------------------------------------------------------------+
//| GerenciarPosicaoAberta                                           |
//| Responsabilidade: aplicar trailing stop, validar stop/gain       |
//| financeiro e fechar por enfraquecimento do sinal (v_Analise).    |
//| Executada a CADA TICK para reagir imediatamente ao preco. O      |
//| v_Analise recebido e o ultimo calculado no fechamento do candle. |
//+------------------------------------------------------------------+
void GerenciarPosicaoAberta(const int v_Analise)
{
   if(!SelecionarPosicao())
      return;

   ENUM_POSITION_TYPE tipo    = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double precoEntrada        = PositionGetDouble(POSITION_PRICE_OPEN);
   double precoAtual          = (tipo == POSITION_TYPE_BUY)
                                ? SymbolInfoDouble(CodigoAtivo, SYMBOL_BID)
                                : SymbolInfoDouble(CodigoAtivo, SYMBOL_ASK);
   ENUM_DIRECAO direcao       = (tipo == POSITION_TYPE_BUY) ? DIRECAO_COMPRA : DIRECAO_VENDA;

   // 1) Stop movel: protege o resultado ja conquistado.
   TrailStopControl(precoAtual, precoEntrada, StopOperacao, direcao);

   // 2) Stop financeiro por operacao.
   ValidarStopOperacao();
   if(!SelecionarPosicao()) return; // Pode ter fechado no passo anterior.

   // 3) Gain financeiro por operacao.
   ValidarGainOperacao();
   if(!SelecionarPosicao()) return;

   // 4) Fechamento por enfraquecimento do sinal:
   //    - compra fecha quando v_Analise <= Risco_Fechamento
   //    - venda  fecha quando v_Analise >= Risco_Fechamento
   if(!ValidationMode)
     {
         if(tipo == POSITION_TYPE_BUY && v_Analise <= Risco_Fechamento)
         FecharPosicao("Sinal de compra enfraqueceu (v_Analise <= Risco_Fechamento)");
      else if(tipo == POSITION_TYPE_SELL && v_Analise >= Risco_Fechamento)
         FecharPosicao("Sinal de venda enfraqueceu (v_Analise >= Risco_Fechamento)");
     }
   

}

void GerenciarPosicaoAbertaPontos(const int v_Analise)
{
   if(!SelecionarPosicao())
      return;

   ENUM_POSITION_TYPE tipo    = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double precoEntrada        = PositionGetDouble(POSITION_PRICE_OPEN);
   double precoAtual          = (tipo == POSITION_TYPE_BUY)
                                ? SymbolInfoDouble(CodigoAtivo, SYMBOL_BID)
                                : SymbolInfoDouble(CodigoAtivo, SYMBOL_ASK);
   ENUM_DIRECAO direcao       = (tipo == POSITION_TYPE_BUY) ? DIRECAO_COMPRA : DIRECAO_VENDA;

   // 1) Stop movel: protege o resultado ja conquistado.
   TrailStopControl(precoAtual, precoEntrada, StopOperacao, direcao);

   // 2) Stop financeiro por operacao.
   ValidarStopOperacao();
   if(!SelecionarPosicao()) return; // Pode ter fechado no passo anterior.

   // 3) Gain financeiro por operacao.
   ValidarGainOperacao();
   if(!SelecionarPosicao()) return;

   // 4) Fechamento por enfraquecimento do sinal:
   //    - compra fecha quando v_Analise <= Risco_Fechamento
   //    - venda  fecha quando v_Analise >= Risco_Fechamento
   if(!ValidationMode)
     {
         if(tipo == POSITION_TYPE_BUY && v_Analise <= Risco_Fechamento)
         FecharPosicao("Sinal de compra enfraqueceu (v_Analise <= Risco_Fechamento)");
      else if(tipo == POSITION_TYPE_SELL && v_Analise >= Risco_Fechamento)
         FecharPosicao("Sinal de venda enfraqueceu (v_Analise >= Risco_Fechamento)");
     }
   

}
//+------------------------------------------------------------------+
//| TrailStopControl                                                 |
//| Responsabilidade: mover o stop a favor do resultado para impedir |
//| que uma operacao que ja superou o valor de StopOperacao em lucro |
//| devolva o ganho e feche no negativo.                             |
//| Parametros: preco atual, preco de entrada, StopOperacao, direcao |
//+------------------------------------------------------------------+
void TrailStopControl(const double precoAtual,
                      const double precoEntrada,
                      const double valorStop,
                      const ENUM_DIRECAO direcao)
{
   double volume   = PositionGetDouble(POSITION_VOLUME);
   double slAtual  = PositionGetDouble(POSITION_SL);
   double tpAtual  = PositionGetDouble(POSITION_TP);
   double ponto    = SymbolInfoDouble(CodigoAtivo, SYMBOL_POINT);
   int    digitos  = (int)SymbolInfoInteger(CodigoAtivo, SYMBOL_DIGITS);

   // Distancia de preco equivalente, em dinheiro, ao valor de StopOperacao.
   double distGatilho = DistanciaPrecoPorValor(valorStop, volume);
   double distTrail   = Trail_stop * ponto;

   if(distGatilho <= 0.0)
      return; // Nao foi possivel converter o valor monetario em distancia.

   if(direcao == DIRECAO_COMPRA)
   {
      double lucroEmPreco = precoAtual - precoEntrada;
      // So move o stop depois que o lucro supera o gatilho.
      if(lucroEmPreco > distGatilho)
      {
         double novoSL = precoAtual - distTrail;
         if(novoSL < precoEntrada) novoSL = precoEntrada; // Nunca abaixo do break-even.
         novoSL = NormalizeDouble(novoSL, digitos);

         // So atualiza se melhorar (subir) ao menos 1 ponto, evitando
         // enviar uma modificacao a cada tick desnecessariamente.
         if(novoSL > slAtual + ponto)
            if(!g_trade.PositionModify(CodigoAtivo, novoSL, tpAtual))
               Print("[TrailStop] Falha ao mover stop (compra): ", g_trade.ResultRetcodeDescription());
      }
   }
   else // DIRECAO_VENDA
   {
      double lucroEmPreco = precoEntrada - precoAtual;
      if(lucroEmPreco > distGatilho)
      {
         double novoSL = precoAtual + distTrail;
         if(novoSL > precoEntrada) novoSL = precoEntrada; // Nunca acima do break-even.
         novoSL = NormalizeDouble(novoSL, digitos);

         // So atualiza se melhorar (descer) ao menos 1 ponto, evitando
         // enviar uma modificacao a cada tick desnecessariamente.
         if(slAtual == 0.0 || novoSL < slAtual - ponto)
            if(!g_trade.PositionModify(CodigoAtivo, novoSL, tpAtual))
               Print("[TrailStop] Falha ao mover stop (venda): ", g_trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| ValidarStopOperacao                                              |
//| Responsabilidade: garantir que a perda de uma operacao aberta    |
//| nunca exceda o prejuizo maximo configurado em StopOperacao.      |
//+------------------------------------------------------------------+
void ValidarStopOperacao()
{
   if(StopOperacao <= 0.0)
      return;

   double lucro = PositionGetDouble(POSITION_PROFIT); // Resultado flutuante (em dinheiro)

   // Se a perda atinge/excede o limite, encerra a operacao imediatamente.
   if(lucro <= -StopOperacao)
      FecharPosicao("StopOperacao atingido (perda maxima por operacao)");
}

//+------------------------------------------------------------------+
//| ValidarGainOperacao                                              |
//| Responsabilidade: encerrar a operacao quando o ganho financeiro  |
//| configurado em GainOperacao for atingido.                        |
//|                                                                  |
//| Regra: o parametro GainOperacao e OPCIONAL.                      |
//|   - Se GainOperacao > 0  -> valida e fecha ao atingir o alvo.    |
//|   - Se GainOperacao <= 0 -> nenhum limite de ganho configurado;  |
//|     a operacao prossegue sem analisar este parametro.            |
//+------------------------------------------------------------------+
void ValidarGainOperacao()
{
   // Parametro nao configurado (0 ou negativo): ignora a validacao.
   if(GainOperacao <= 0.0)
      return;

   double lucro = PositionGetDouble(POSITION_PROFIT); // Resultado flutuante (em dinheiro)

   // Alvo de ganho alcancado -> realiza o lucro.
   if(lucro >= GainOperacao)
      FecharPosicao("GainOperacao atingido (alvo de ganho por operacao)");
}
//==================================================================//
//  SECAO 7 - VALIDACOES DIARIAS E DE JANELA DE HORARIO              //
//==================================================================//

//+------------------------------------------------------------------+
//| LimiteOperacoesDiaAtingido                                       |
//| Retorna true quando a qtd. maxima de operacoes do dia foi atingida.|
//+------------------------------------------------------------------+
bool LimiteOperacoesDiaAtingido()
{
   if(MaxOperacoesDia > 0 && CountOperacoesDia >= MaxOperacoesDia)
      return true;
   return false;
}

//+------------------------------------------------------------------+
//| LimiteStopDiaAtingido                                            |
//| Retorna true quando a perda acumulada do dia atingiu o limite.   |
//| OBS: MaxStopDia e informado como valor POSITIVO (modulo da perda)|
//| e a parada ocorre quando ResultadoTotalDia <= -MaxStopDia.       |
//+------------------------------------------------------------------+
bool LimiteStopDiaAtingido()
{
   if(MaxStopDia > 0 && ResultadoTotalDia <= -MaxStopDia)
      return true;
   return false;
}

//+------------------------------------------------------------------+
//| LimiteMetaDiaAtingido                                            |
//| Retorna true quando a meta de resultado do dia foi alcancada     |
//| (ResultadoTotalDia >= MaxMetaDia).                               |
//+------------------------------------------------------------------+
bool LimiteMetaDiaAtingido()
{
   if(MaxMetaDia > 0 && ResultadoTotalDia >= MaxMetaDia)
      return true;
   return false;
}

//+------------------------------------------------------------------+
//| DentroDoHorario                                                  |
//| Responsabilidade: liberar a execucao apenas dentro da janela     |
//| [HoraInicioExecucao, HoraFimExecucao]. Datetime = 0 significa    |
//| "nao configurado" (sem restricao naquele limite). A comparacao   |
//| considera apenas o horario (hora:min:seg) do dia corrente.       |
//+------------------------------------------------------------------+
bool DentroDoHorario()
{
   MqlDateTime agora;
   TimeToStruct(TimeCurrent(), agora);
   int segAgora = agora.hour * 3600 + agora.min * 60 + agora.sec;

   if(HoraInicioExecucao > 0)
   {
      MqlDateTime ini;
      TimeToStruct(HoraInicioExecucao, ini);
      int segIni = ini.hour * 3600 + ini.min * 60 + ini.sec;
      if(segAgora < segIni)
         return false; // Ainda nao chegou no horario de inicio.
   }

   if(HoraFimExecucao > 0)
   {
      MqlDateTime fim;
      TimeToStruct(HoraFimExecucao, fim);
      int segFim = fim.hour * 3600 + fim.min * 60 + fim.sec;
      if(segAgora > segFim)
         return false; // Ja passou do horario de fim.
   }

   return true;
}

//==================================================================//
//  SECAO 8 - FUNCOES AUXILIARES DE POSICAO E EXECUCAO               //
//==================================================================//

//+------------------------------------------------------------------+
//| TemPosicao                                                       |
//| Retorna true se existir posicao aberta deste robo (ativo+Magic). |
//+------------------------------------------------------------------+
bool TemPosicao()
{
   return SelecionarPosicao();
}

//+------------------------------------------------------------------+
//| SelecionarPosicao                                                |
//| Seleciona a posicao do ativo/Magic deste robo, deixando-a ativa  |
//| para as chamadas PositionGet*. Retorna true se encontrar.        |
//+------------------------------------------------------------------+
bool SelecionarPosicao()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i); // Seleciona a posicao pelo indice.
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == CodigoAtivo &&
         (int)PositionGetInteger(POSITION_MAGIC) == MagicId)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| AbrirOperacao                                                    |
//| Responsabilidade: abrir uma ordem a mercado na direcao indicada, |
//| ja com stop inicial baseado em StopOperacao (protecao no broker).|
//+------------------------------------------------------------------+
void AbrirOperacao(const ENUM_DIRECAO direcao)
{
   double volume  = ValidarVolume(Alavancagem);
   int    digitos = (int)SymbolInfoInteger(CodigoAtivo, SYMBOL_DIGITS);
   double distSL  = DistanciaPrecoPorValor(StopOperacao, volume);

   if(direcao == DIRECAO_COMPRA)
   {
      double preco = SymbolInfoDouble(CodigoAtivo, SYMBOL_ASK);
      double sl    = (distSL > 0.0) ? NormalizeDouble(preco - distSL, digitos) : 0.0;

      if(!g_trade.Buy(volume, CodigoAtivo, preco, sl, 0.0, "Compra EA"))
         Print("[AbrirOperacao] Falha ao abrir COMPRA: ", g_trade.ResultRetcodeDescription());
      else
         Print("[AbrirOperacao] Compra aberta. Volume=", volume, " Preco=", preco);
   }
   else // DIRECAO_VENDA
   {
      double preco = SymbolInfoDouble(CodigoAtivo, SYMBOL_BID);
      double sl    = (distSL > 0.0) ? NormalizeDouble(preco + distSL, digitos) : 0.0;

      if(!g_trade.Sell(volume, CodigoAtivo, preco, sl, 0.0, "Venda EA"))
         Print("[AbrirOperacao] Falha ao abrir VENDA: ", g_trade.ResultRetcodeDescription());
      else
         Print("[AbrirOperacao] Venda aberta. Volume=", volume, " Preco=", preco);
   }
}

//+------------------------------------------------------------------+
//| FecharPosicao                                                    |
//| Responsabilidade: encerrar a posicao aberta deste robo e         |
//| registrar o motivo do fechamento.                                |
//+------------------------------------------------------------------+
void FecharPosicao(const string motivo)
{
   if(!g_trade.PositionClose(CodigoAtivo))
      Print("[FecharPosicao] Falha ao fechar (", motivo, "): ", g_trade.ResultRetcodeDescription());
   else
      Print("[FecharPosicao] Posicao encerrada. Motivo: ", motivo);
}

//+------------------------------------------------------------------+
//| ValidarVolume                                                    |
//| Responsabilidade: ajustar o volume (Alavancagem) para a faixa    |
//| permitida (0.01 a 10) e aos limites/step do ativo.               |
//+------------------------------------------------------------------+
double ValidarVolume(const double volumeDesejado)
{
   double minVol = SymbolInfoDouble(CodigoAtivo, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(CodigoAtivo, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(CodigoAtivo, SYMBOL_VOLUME_STEP);

   double v = volumeDesejado;

   // Faixa do parametro Alavancagem: 0.01 ate 10.
   if(v < 0.01) v = 0.01;
   if(v > 10.0) v = 10.0;

   // Respeita os limites do ativo.
   if(v < minVol) v = minVol;
   if(v > maxVol) v = maxVol;

   // Alinha ao passo de volume do ativo.
   if(step > 0.0)
      v = MathRound(v / step) * step;

   return NormalizeDouble(v, 2);
}

//+------------------------------------------------------------------+
//| DistanciaPrecoPorValor                                           |
//| Converte um valor monetario em distancia de preco para o volume  |
//| informado (usa tick value / tick size do ativo).                 |
//+------------------------------------------------------------------+
double DistanciaPrecoPorValor(const double valorMonetario, const double volume)
{
   double tickValue = SymbolInfoDouble(CodigoAtivo, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(CodigoAtivo, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0 || volume <= 0.0)
      return 0.0;

   // Dinheiro ganho/perdido por 1.0 de variacao de preco, no volume informado.
   double valorPorPrecoUnit = (tickValue / tickSize) * volume;
   if(valorPorPrecoUnit <= 0.0)
      return 0.0;

   return valorMonetario / valorPorPrecoUnit;
}

//+------------------------------------------------------------------+
//| AtualizarEstatisticasDia                                         |
//| Responsabilidade: recalcular ResultadoTotalDia e CountOperacoesDia|
//| a partir do historico de negocios do dia + resultado flutuante   |
//| da posicao aberta. Recalcular a cada execucao zera naturalmente  |
//| os contadores na virada do dia.                                  |
//+------------------------------------------------------------------+
void AtualizarEstatisticasDia()
{
   // Inicio do dia corrente (00:00:00).
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime inicioDia = StructToTime(dt);

   double resultado = 0.0;
   int    contador  = 0;

   if(HistorySelect(inicioDia, TimeCurrent()))
   {
      int totalDeals = HistoryDealsTotal();
      for(int i = 0; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;

         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != CodigoAtivo)        continue;
         if((int)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicId)       continue;

         resultado += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

         // Conta apenas os negocios de ENTRADA (abertura de posicao).
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            contador++;
      }
   }
   else
   {
      Print("[AtualizarEstatisticasDia] Falha ao selecionar historico. Codigo: ", GetLastError());
   }

   // Inclui o resultado flutuante da posicao aberta (se houver) nos limites diarios.
   if(SelecionarPosicao())
      resultado += PositionGetDouble(POSITION_PROFIT);

   ResultadoTotalDia = resultado;
   CountOperacoesDia = (double)contador;
}

//+------------------------------------------------------------------+
//| NovaBarra                                                        |
//| Retorna true uma unica vez por barra (quando o candle anterior   |
//| fecha). Base do evento "candle:closed".                          |
//+------------------------------------------------------------------+
bool NovaBarra()
{
   datetime tempoBarra = iTime(CodigoAtivo, PERIOD_CURRENT, 0);
   if(tempoBarra == g_tempoUltimaBarra)
      return false;

   g_tempoUltimaBarra = tempoBarra; // Nova barra abriu => barra anterior fechou.
   return true;
}
