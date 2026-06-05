//+------------------------------------------------------------------------+
//|                                              MetaOperador2.mq5         |
//|                                  Copyright 2026, Trade em Foco         |
//|                                  https://www.tradeemfoco.com.br        |
//|                                                                        |
//|   Expert Advisor profissional com sistema de score ponderado           |
//|   Baseado na arquitetura MetaOperador 1.0 + Especificacao 2.0          |
//|                                                                        |
//|   Arquitetura em camadas:                                              |
//|     Camada 1 - Coleta de Dados (M1 + contexto M3/M5)                   |
//|     Camada 2 - Modulos de Analise (score)                              |
//|     Camada 3 - Sistema de Pesos                                        |
//|     Camada 4 - Habilitacao de Estrategias                              |
//|                                                                        |
//|   Logica de Gestao por Estagios de R:                                  |
//|     2.0R atingido -> protege em 0R (break even)                        |
//|     4.0R atingido -> protege em 1.0R                                   |
//|     6.0R atingido -> trailing de 3R atras do preco atual               |
//|                                                                        |
//|   ESTE CODIGO NAO E RECOMENDACAO FINANCEIRA.                           |
//|   Realize backtest no Strategy Tester antes de usar em conta real.     |
//+------------------------------------------------------------------------+

#property copyright "Copyright 2026, Trade em Foco"
#property link      "https://www.tradeemfoco.com.br"
#property version   "2.05"
#property strict

#include <Trade/Trade.mqh>

//==================================================================//
//  SECAO 1 - CONSTANTES                                             //
//==================================================================//

#define RSI_PERIODO        14
#define STO_K_PERIODO      14
#define STO_D_PERIODO      3
#define STO_SLOWING        3
#define EMA_RAPIDA         20
#define EMA_MEDIA          50
#define EMA_LENTA          72
#define LOOKBACK_LIQUIDEZ  30
#define LOOKBACK_ESTRUTURA 50
#define ATR_PERIODO        14

enum ENUM_DIRECAO
{
   DIRECAO_COMPRA =  1,
   DIRECAO_VENDA  = -1
};

//==================================================================//
//  SECAO 2 - PARAMETROS DE ENTRADA: CONFIGURACAO GERAL             //
//==================================================================//

input string   CodigoAtivo          = "XAUUSD";       // Ativo operado
input int   MagicId              = 05062026;    // Magic Number

//--- Horario
input int      GMTOffsetBrasil      = -6;        // Horario de Brasilia (GMT offset)
input int      GMTOffsetBroker      = 0;         // Horario da Corretora (GMT offset)
input datetime HoraInicioExecucao   = 0;         // Horario inicio (0=sem restricao)
input datetime HoraFimExecucao      = 0;         // Horario fim    (0=sem restricao)

//--- Sessoes
input bool     OperarLondres        = true;     // Operar sessao Londres
input bool     OperarNovaYork       = true;      // Operar sessao Nova York
input bool     OperarAsia           = false;     // Operar sessao Asia

//==================================================================//
//  SECAO 3 - PARAMETROS: GESTAO DE RISCO                           //
//==================================================================//

input bool     UseRiskPercent       = false;     // Usar risco percentual automatico
input double   RiskPercent          = 0;       // Risco por operacao (% do saldo)
input double   LoteFixo             = 0.01;      // Lote fixo (usado se UseRiskPercent=false)

//--- Stop
input int      StopInicialPontos    = 190;       // Stop Loss inicial fixo (pontos = 1R)

//--- Filtros
input int      MaxSpread            = 10;        // Spread maximo permitido (pontos)
input double   ATRMinimo            = 0;     // ATR minimo para operar (pontos)

//--- Filtros de EMA
input double   DistanciaMinimaEMA72 = 100;       // Distancia minima do preco para EMA72 (pontos)
input int      EMA20_MinSlopePoints = 10;        // Inclinacao minima da EMA20 (pontos/candle)

//--- Filtro VWAP
input int      VWAP_MinDistance     = 100;       // Distancia minima do preco para VWAP (pontos)

//--- Filtro de RSI
input int      RSICompra            = 40;        // 
input int      RSIVenda             = 60;        // 

//==================================================================//
//  SECAO 4 - PARAMETROS: CONTROLE OPERACIONAL                      //
//==================================================================//

input int      MaxOperacoesDia      = 0;         // Max operacoes por dia (0=ilimitado)
input double   MaxStopDia           = 0;         // Stop diario maximo em $ (0=desativado)
input double   MaxMetaDia           = 0;         // Meta diaria em $ (0=desativado)
input int      MaxStopsSeguidos     = 0;         // Max stops consecutivos (0=desativado)
input int      MaxWinsSeguidos      = 0;         // Max wins consecutivos (0=desativado)
input int      CooldownCandles      = 0;         // Candles de cooldown apos stop

//==================================================================//
//  SECAO 5 - PARAMETROS: PESOS DAS ANALISES                        //
//==================================================================//

input int      PesoRSI              = 1;         // Peso RSI
input int      PesoLiquidez         = 2;         // Peso Limpeza de Liquidez
input int      PesoTendencia        = 2;         // Peso Tendencia EMAs M1
input int      PesoContinuidade     = 1;         // Peso Continuidade
input int      PesoEstrutura        = 3;         // Peso Estrutura de Mercado
input int      PesoCHOCH            = 4;         // Peso CHOCH
input int      PesoBOS              = 4;         // Peso BOS
input int      PesoFVG              = 2;         // Peso FVG
input int      PesoOrderBlock       = 2;         // Peso Order Block
input int      PesoCandle           = 1;         // Peso Forca do Candle
input int      PesoEstocastico      = 1;         // Peso Estocastico
input int      PesoVWAP             = 2;         // Peso VWAP
input int      PesoEMA              = 3;         // Peso Cruzamento EMA M1
input int      PesoTendenciaM3      = 2;         // Peso Tendencia M3
input int      PesoTendenciaM5      = 3;         // Peso Tendencia M5
input int      PesoDivergenciaRSI   = 2;         // Peso Divergencia RSI
input int      PesoRejeicaoWick     = 2;         // Peso Rejeicao Wick
input int      PesoEngolfo          = 3;         // Peso Engolfo

//==================================================================//
//  SECAO 5.1 - PARAMETROS: REGIME DE MERCADO                                   //
//==================================================================//

input bool UseRegimeMercado = true;
input int DistanciaMinimaEMAs = 100;

//==================================================================//
//  SECAO 6 - PARAMETROS: HABILITACAO DE ESTRATEGIAS                //
//==================================================================//

input bool     UsePivotRSI          = true;      // Usar (1)  RSI
input bool     UseLiquidez          = true;      // Usar (2)  Limpeza de Liquidez
input bool     UseTendencia         = true;      // Usar (3)  Tendencia EMAs M1
input bool     UseContinuidade      = true;      // Usar (4)  Continuidade
input bool     UseEstrutura         = true;      // Usar (5)  Estrutura de Mercado
input bool     UseCHOCH             = true;      // Usar (6)  CHOCH
input bool     UseBOS               = true;      // Usar (7)  BOS
input bool     UseFVG               = true;      // Usar (8)  FVG
input bool     UseOrderBlock        = true;      // Usar (9)  Order Block
input bool     UseForcaCandle       = true;      // Usar (10) Forca do Candle
input bool     UseEstocastico       = true;      // Usar (11) Estocastico
input bool     UseVWAP              = true;      // Usar (12) VWAP
input bool     UseCruzamentoEMA     = true;      // Usar (13) Cruzamento EMA20/EMA50 M1
input bool     UseTendenciaM3       = true;      // Usar (14) Tendencia M3
input bool     UseTendenciaM5       = true;      // Usar (15) Tendencia M5
input bool     UseDivergenciaRSI    = true;      // Usar (16) Divergencia RSI
input bool     UseRejeicaoWick      = true;      // Usar (17) Rejeicao de Wick
input bool     UseEngolfo           = true;      // Usar (18) Engolfo

//==================================================================//
//  SECAO 7 - PARAMETROS: SCORE MINIMO DE ENTRADA                   //
//==================================================================//

input int      ScoreMinimoCompra    = 13;        // Score minimo para COMPRA
input int      ScoreMinimoVenda     = -13;       // Score minimo para VENDA (negativo)

//==================================================================//
//  SECAO 8 - PARAMETROS: VALIDACAO E LOGS                          //
//==================================================================//

input bool     ValidationMode       = false;     // Modo de validacao individual
input int      ValidationNumber     = 0;         // Modulo a validar (1-18)

input bool     LogRSI               = false;     // Log RSI
input bool     LogLiquidez          = false;     // Log Liquidez
input bool     LogTendencia         = false;     // Log Tendencia
input bool     LogScore             = false;     // Log Score calculado
input bool     LogEntrada           = false;     // Log entradas
input bool     LogSaida             = false;     // Log saidas
input bool     LogGestao            = false;     // Log gestao de risco (estagios R)

//==================================================================//
//  SECAO 9 - VARIAVEIS INTERNAS / ESTADO GLOBAL                    //
//==================================================================//

CTrade g_trade;

//--- Handles M1
int g_handleRSI   = INVALID_HANDLE;
int g_handleStoch = INVALID_HANDLE;
int g_handleEMA20 = INVALID_HANDLE;
int g_handleEMA50 = INVALID_HANDLE;
int g_handleEMA72 = INVALID_HANDLE;
int g_handleATR   = INVALID_HANDLE;

//--- Handles M3 e M5
int g_handleEMA20_M3 = INVALID_HANDLE;
int g_handleEMA50_M3 = INVALID_HANDLE;
int g_handleEMA20_M5 = INVALID_HANDLE;
int g_handleEMA50_M5 = INVALID_HANDLE;

//--- Controle de tempo
datetime g_tempoUltimaBarra    = 0;
datetime g_ultimoCandleOperado = 0;
int      g_candlesCooldown     = 0;

//--- Score e regime
int g_scoreFinal = 0;
int g_regime     = 0; // 0=indefinido, 1=tendencia, 2=lateral, 3=manipulacao

//--- Estatisticas do dia
double g_resultadoDia    = 0.0;
int    g_operacoesDia    = 0;
int    g_stopsSeguidos   = 0;
int    g_winsSeguidos    = 0;
double g_ultimoResultado = 0.0;

//--- Estagios de protecao por R
bool g_estagio1Ativado = false; // 2.0R -> Break Even
bool g_estagio2Ativado = false; // 4.0R -> SL em 1.0R
bool g_estagio3Ativado = false; // 6.0R -> Trailing 3R

//==================================================================//
//  SECAO 10 - CACHE DE DADOS (atualizado a cada nova barra)        //
//==================================================================//

//--- M1
double g_rsi    = 0.0;
double g_stochK = 0.0;
double g_stochD = 0.0;
double g_ema20  = 0.0;
double g_ema50  = 0.0;
double g_ema72  = 0.0;
double g_atr    = 0.0;

//--- M3
double g_ema20_M3 = 0.0;
double g_ema50_M3 = 0.0;

//--- M5
double g_ema20_M5 = 0.0;
double g_ema50_M5 = 0.0;

//--- Gerais
double g_spreadAtual = 0.0;
double g_vwap        = 0.0;

//--- RSI da barra anterior (para divergencia)
// FIX #2: variavel global garante que rsiPrev e atualizado corretamente
double g_rsiPrev = 0.0;

//--- Price action M1 (ArraySetAsSeries=true: [0]=candle fechado mais recente)
MqlRates g_rates[];

//==================================================================//
//  SECAO 11 - CONTROLE DE CANDLE                                   //
//==================================================================//

bool NovaBarra()
{
   datetime tempoBarra = iTime(CodigoAtivo, PERIOD_CURRENT, 0);
   if(tempoBarra == g_tempoUltimaBarra) return false;
   g_tempoUltimaBarra = tempoBarra;
   return true;
}

void ResetEstagiosSeSemPosicao()
{
   if(!TemPosicao())
   {
      g_estagio1Ativado = false;
      g_estagio2Ativado = false;
      g_estagio3Ativado = false;
   }
}

//==================================================================//
//  SECAO 12 - EVENT HANDLERS                                        //
//==================================================================//

int OnInit()
{
   g_trade.SetExpertMagicNumber  (MagicId);
   g_trade.SetTypeFillingBySymbol(CodigoAtivo);
   g_trade.SetDeviationInPoints  (10);

   //--- M1
   g_handleStoch = iStochastic(CodigoAtivo, PERIOD_CURRENT,
                                STO_K_PERIODO, STO_D_PERIODO, STO_SLOWING,
                                MODE_SMA, STO_LOWHIGH);
   g_handleRSI   = iRSI(CodigoAtivo, PERIOD_CURRENT, RSI_PERIODO,   PRICE_CLOSE);
   g_handleEMA20 = iMA (CodigoAtivo, PERIOD_CURRENT, EMA_RAPIDA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleEMA50 = iMA (CodigoAtivo, PERIOD_CURRENT, EMA_MEDIA,  0, MODE_EMA, PRICE_CLOSE);
   g_handleEMA72 = iMA (CodigoAtivo, PERIOD_CURRENT, EMA_LENTA,  0, MODE_EMA, PRICE_CLOSE);
   g_handleATR   = iATR(CodigoAtivo, PERIOD_CURRENT, ATR_PERIODO);

   //--- M3 e M5
   g_handleEMA20_M3 = iMA(CodigoAtivo, PERIOD_M3, EMA_RAPIDA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleEMA50_M3 = iMA(CodigoAtivo, PERIOD_M3, EMA_MEDIA,  0, MODE_EMA, PRICE_CLOSE);
   g_handleEMA20_M5 = iMA(CodigoAtivo, PERIOD_M5, EMA_RAPIDA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleEMA50_M5 = iMA(CodigoAtivo, PERIOD_M5, EMA_MEDIA,  0, MODE_EMA, PRICE_CLOSE);

   if(g_handleRSI      == INVALID_HANDLE || g_handleStoch    == INVALID_HANDLE ||
      g_handleEMA20    == INVALID_HANDLE || g_handleEMA50    == INVALID_HANDLE ||
      g_handleEMA72    == INVALID_HANDLE || g_handleATR      == INVALID_HANDLE ||
      g_handleEMA20_M3 == INVALID_HANDLE || g_handleEMA50_M3 == INVALID_HANDLE ||
      g_handleEMA20_M5 == INVALID_HANDLE || g_handleEMA50_M5 == INVALID_HANDLE)
   {
      Print("[OnInit] ERRO ao criar handles. Codigo: ", GetLastError());
      return INIT_FAILED;
   }

   ArraySetAsSeries(g_rates, true);
   g_tempoUltimaBarra = iTime(CodigoAtivo, PERIOD_CURRENT, 0);

   Print("[OnInit] MetaOperador 2.05 | Ativo=", CodigoAtivo,
         " | Magic=", MagicId, " | SL=", StopInicialPontos,
         "pts | Estagios: 2R->BE | 4R->1R | 6R->Trailing3R");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_handleRSI      != INVALID_HANDLE) { IndicatorRelease(g_handleRSI);      g_handleRSI      = INVALID_HANDLE; }
   if(g_handleStoch    != INVALID_HANDLE) { IndicatorRelease(g_handleStoch);    g_handleStoch    = INVALID_HANDLE; }
   if(g_handleEMA20    != INVALID_HANDLE) { IndicatorRelease(g_handleEMA20);    g_handleEMA20    = INVALID_HANDLE; }
   if(g_handleEMA50    != INVALID_HANDLE) { IndicatorRelease(g_handleEMA50);    g_handleEMA50    = INVALID_HANDLE; }
   if(g_handleEMA72    != INVALID_HANDLE) { IndicatorRelease(g_handleEMA72);    g_handleEMA72    = INVALID_HANDLE; }
   if(g_handleATR      != INVALID_HANDLE) { IndicatorRelease(g_handleATR);      g_handleATR      = INVALID_HANDLE; }
   if(g_handleEMA20_M3 != INVALID_HANDLE) { IndicatorRelease(g_handleEMA20_M3); g_handleEMA20_M3 = INVALID_HANDLE; }
   if(g_handleEMA50_M3 != INVALID_HANDLE) { IndicatorRelease(g_handleEMA50_M3); g_handleEMA50_M3 = INVALID_HANDLE; }
   if(g_handleEMA20_M5 != INVALID_HANDLE) { IndicatorRelease(g_handleEMA20_M5); g_handleEMA20_M5 = INVALID_HANDLE; }
   if(g_handleEMA50_M5 != INVALID_HANDLE) { IndicatorRelease(g_handleEMA50_M5); g_handleEMA50_M5 = INVALID_HANDLE; }

   ExibirEstatisticasFinais();
   Print("[OnDeinit] MetaOperador 2.05 finalizado. Motivo: ", reason);
}

void OnTick()
{
   g_spreadAtual = (double)SymbolInfoInteger(CodigoAtivo, SYMBOL_SPREAD);

   ResetEstagiosSeSemPosicao();

   // =====================================================
   // ATUALIZACAO PESADA -> SOMENTE NOVA BARRA
   // =====================================================
   if(NovaBarra())
   {
      g_rsiPrev = g_rsi;

      AtualizarDadosMercado();

      g_vwap = CalcularVWAP();

      AtualizarEstatisticasDia();

      if(LogScore)
         Print("[NOVA BARRA] Dados estruturais atualizados.");
   }

   // =====================================================
   // ATUALIZACAO RAPIDA -> TODO TICK
   // =====================================================

   AtualizarCandleAtual();

   g_regime     = DetectarRegime();
   g_scoreFinal = CalcularScore();

   ExecutarEstrategia();

   // =====================================================
   // GESTAO DA POSICAO
   // =====================================================

   if(TemPosicao())
      GerenciarPosicaoAberta();
}

//==================================================================//
//  SECAO 13 - ATUALIZAR CANDLE ATUAL                               //
//==================================================================//

void AtualizarCandleAtual()
{
   MqlRates atual[];

   ArraySetAsSeries(atual, true);

   if(CopyRates(CodigoAtivo, PERIOD_CURRENT, 0, 1, atual) < 1)
      return;

   g_rates[0] = atual[0];
}

//==================================================================//
//  SECAO 14 - CAMADA 1: COLETA DE DADOS                            //
//==================================================================//

void AtualizarDadosMercado()
{
   double buf1[1];

   //--- M1
   if(CopyBuffer(g_handleRSI,   0, 1, 1, buf1) >= 1) g_rsi    = buf1[0];
   if(CopyBuffer(g_handleStoch, 0, 1, 1, buf1) >= 1) g_stochK = buf1[0];
   if(CopyBuffer(g_handleStoch, 1, 1, 1, buf1) >= 1) g_stochD = buf1[0];
   if(CopyBuffer(g_handleEMA20, 0, 1, 1, buf1) >= 1) g_ema20  = buf1[0];
   if(CopyBuffer(g_handleEMA50, 0, 1, 1, buf1) >= 1) g_ema50  = buf1[0];
   if(CopyBuffer(g_handleEMA72, 0, 1, 1, buf1) >= 1) g_ema72  = buf1[0];
   if(CopyBuffer(g_handleATR,   0, 1, 1, buf1) >= 1) g_atr    = buf1[0];

   //--- M3
   if(CopyBuffer(g_handleEMA20_M3, 0, 1, 1, buf1) >= 1) g_ema20_M3 = buf1[0];
   if(CopyBuffer(g_handleEMA50_M3, 0, 1, 1, buf1) >= 1) g_ema50_M3 = buf1[0];

   //--- M5
   if(CopyBuffer(g_handleEMA20_M5, 0, 1, 1, buf1) >= 1) g_ema20_M5 = buf1[0];
   if(CopyBuffer(g_handleEMA50_M5, 0, 1, 1, buf1) >= 1) g_ema50_M5 = buf1[0];

   //--- Price action M1
   int qtd = MathMax(LOOKBACK_ESTRUTURA, LOOKBACK_LIQUIDEZ);
   CopyRates(CodigoAtivo, PERIOD_CURRENT, 1, qtd, g_rates);
}

//==================================================================//
//  SECAO 15 - CAMADA 2: MODULOS DE ANALISE                         //
//  Retorna +1 (compra), -1 (venda) ou 0 (neutro)                   //
//==================================================================//

//+------------------------------------------------------------------+
//| PivotRSI  [Modulo 1]                                             |
//+------------------------------------------------------------------+
int PivotRSI()
{
   double bufferRSI[];

   if(CopyBuffer(g_handleRSI,0,0,1,bufferRSI) < 1)
      return 0;

   double rsi = bufferRSI[0];

   int tendencia = Tendencia();

   if(tendencia > 0)
   {
      if(rsi <= RSICompra)
         return 1;
   }

   if(tendencia < 0)
   {
      if(rsi >= RSIVenda)
         return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| LimpezaLiquidez  [Modulo 2]                                      |
//+------------------------------------------------------------------+
int LimpezaLiquidez()
{
   int total = ArraySize(g_rates);
   if(total < LOOKBACK_LIQUIDEZ) { Print("[LimpezaLiquidez] Dados insuficientes."); return 0; }

   double topoAnterior  = g_rates[3].high;
   double fundoAnterior = g_rates[3].low;
   for(int i = 3; i < LOOKBACK_LIQUIDEZ && i < total; i++)
   {
      if(g_rates[i].high > topoAnterior)  topoAnterior  = g_rates[i].high;
      if(g_rates[i].low  < fundoAnterior) fundoAnterior = g_rates[i].low;
   }

   if(g_rates[0].high > topoAnterior && g_rates[0].close < topoAnterior)
   {
      if(LogLiquidez) Print("[Liquidez] Sweep de topo -> VENDA");
      return -1;
   }
   if(g_rates[0].low < fundoAnterior && g_rates[0].close > fundoAnterior)
   {
      if(LogLiquidez) Print("[Liquidez] Sweep de fundo -> COMPRA");
      return 1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Tendencia  [Modulo 3] - M1                                       |
//+------------------------------------------------------------------+
int Tendencia()
{
   if(g_ema20 >= g_ema50 && g_ema50 >= g_ema72) { if(LogTendencia) Print("[Tendencia M1] Alta");  return  1; }
   if(g_ema20 <= g_ema50 && g_ema50 <= g_ema72) { if(LogTendencia) Print("[Tendencia M1] Baixa"); return -1; }
   return 0;
}

//+------------------------------------------------------------------+
//| Continuidade  [Modulo 4]                                         |
//+------------------------------------------------------------------+
int Continuidade()
{
   MqlRates rates[];

   ArraySetAsSeries(rates,true);

   if(CopyRates(CodigoAtivo,PERIOD_CURRENT,0,3,rates) < 3)
      return 0;

   if(
      rates[0].close > rates[1].close &&
      rates[1].close > rates[2].close
   )
      return 1;

   if(
      rates[0].close < rates[1].close &&
      rates[1].close < rates[2].close
   )
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| EstruturaMercado  [Modulo 5]                                     |
//+------------------------------------------------------------------+
int EstruturaMercado()
{
   int total = ArraySize(g_rates);
   if(total < 10) return 0;

   double h1 = 0, h2 = 0, l1 = DBL_MAX, l2 = DBL_MAX;
   int    hi1 = -1, hi2 = -1, li1 = -1, li2 = -1;

   for(int i = 1; i < total - 1; i++)
   {
      if(g_rates[i].high > g_rates[i-1].high && g_rates[i].high > g_rates[i+1].high)
      {
         if(hi1 == -1)      { h1 = g_rates[i].high; hi1 = i; }
         else if(hi2 == -1) { h2 = g_rates[i].high; hi2 = i; break; }
      }
   }
   for(int i = 1; i < total - 1; i++)
   {
      if(g_rates[i].low < g_rates[i-1].low && g_rates[i].low < g_rates[i+1].low)
      {
         if(li1 == -1)      { l1 = g_rates[i].low; li1 = i; }
         else if(li2 == -1) { l2 = g_rates[i].low; li2 = i; break; }
      }
   }

   if(hi1 == -1 || hi2 == -1 || li1 == -1 || li2 == -1) return 0;
   if((h1 > h2) && (l1 > l2)) return  1; // HH + HL
   if((h1 < h2) && (l1 < l2)) return -1; // LH + LL
   return 0;
}

//+------------------------------------------------------------------+
//| DetectarCHOCH  [Modulo 6]                                        |
//+------------------------------------------------------------------+
int DetectarCHOCH()
{
   int total = ArraySize(g_rates);
   if(total < 10) return 0;

   double ultimoSwingHigh = 0; int idxSwingHigh = -1;
   double ultimoSwingLow  = DBL_MAX; int idxSwingLow = -1;

   for(int i = 1; i < total - 1; i++)
      if(g_rates[i].high > g_rates[i-1].high && g_rates[i].high > g_rates[i+1].high)
         { ultimoSwingHigh = g_rates[i].high; idxSwingHigh = i; break; }

   for(int i = 1; i < total - 1; i++)
      if(g_rates[i].low < g_rates[i-1].low && g_rates[i].low < g_rates[i+1].low)
         { ultimoSwingLow = g_rates[i].low; idxSwingLow = i; break; }

   if(idxSwingHigh != -1 && g_rates[0].close > ultimoSwingHigh && g_ema20 <= g_ema50) return  1;
   if(idxSwingLow  != -1 && g_rates[0].close < ultimoSwingLow  && g_ema20 >= g_ema50) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| DetectarBOS  [Modulo 7]                                          |
//+------------------------------------------------------------------+

int DetectarBOS()
{
   int total = ArraySize(g_rates);
   if(total < 10) return 0;

   double ultimoSwingHigh = 0;
   double ultimoSwingLow  = DBL_MAX;

   for(int i = 1; i < total - 1; i++)
      if(g_rates[i].high > g_rates[i-1].high && g_rates[i].high > g_rates[i+1].high)
         { ultimoSwingHigh = g_rates[i].high; break; }

   for(int i = 1; i < total - 1; i++)
      if(g_rates[i].low < g_rates[i-1].low && g_rates[i].low < g_rates[i+1].low)
         { ultimoSwingLow = g_rates[i].low; break; }

   if(ultimoSwingHigh > 0      && g_rates[0].close > ultimoSwingHigh && g_ema20 > g_ema50) return  1;
   if(ultimoSwingLow < DBL_MAX && g_rates[0].close < ultimoSwingLow  && g_ema20 < g_ema50) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| DetectarFVG  [Modulo 8]                                          |
//+------------------------------------------------------------------+
int DetectarFVG()
{
   if(ArraySize(g_rates) < 3) return 0;
   if(g_rates[2].high < g_rates[0].low)  return  1;
   if(g_rates[2].low  > g_rates[0].high) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| DetectarOrderBlock  [Modulo 9]                                   |
//+------------------------------------------------------------------+
int DetectarOrderBlock()
{
   int total = ArraySize(g_rates);
   if(total < 15) return 0;
   double precoAtual = g_rates[0].close;

   for(int i = 2; i < 15 && i < total - 1; i++)
   {
      if(g_rates[i].close < g_rates[i].open && g_rates[i-1].close > g_rates[i].high)
         if(precoAtual >= g_rates[i].low && precoAtual <= g_rates[i].high) return 1;

      if(g_rates[i].close > g_rates[i].open && g_rates[i-1].close < g_rates[i].low)
         if(precoAtual >= g_rates[i].low && precoAtual <= g_rates[i].high) return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| ForcaCandle  [Modulo 10]                                         |
//+------------------------------------------------------------------+
int ForcaCandle()
{
   if(ArraySize(g_rates) < 1) return 0;
   double corpo     = MathAbs(g_rates[0].close - g_rates[0].open);
   double amplitude = g_rates[0].high - g_rates[0].low;
   if(amplitude <= 0.0 || (corpo / amplitude) < 0.6) return 0;
   return (g_rates[0].close > g_rates[0].open) ? 1 : -1;
}

//+------------------------------------------------------------------+
//| Estocastico  [Modulo 11]                                         |
//+------------------------------------------------------------------+
int Estocastico()
{
   if(g_stochK < 20.0 && g_stochD < 20.0 && g_stochK > g_stochD) return  1;
   if(g_stochK > 80.0 && g_stochD > 80.0 && g_stochK < g_stochD) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| VWAP  [Modulo 12]                                                |
//+------------------------------------------------------------------+
int ModuloVWAP()
{
   if(g_vwap <= 0.0) return 0;
   double distancia = MathAbs(g_rates[0].close - g_vwap) / _Point;
   if(distancia < VWAP_MinDistance) return 0;
   if(g_rates[0].close > g_vwap) return  1;
   if(g_rates[0].close < g_vwap) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Calcular VWAP                   [Modulo 13]                      |
//| Usa barra fechada como limite para evitar barra parcial          |
//+------------------------------------------------------------------+

double CalcularVWAP()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime inicioDia   = StructToTime(dt);
   datetime ultimaBarra = iTime(CodigoAtivo, PERIOD_CURRENT, 1);

   if(ultimaBarra <= inicioDia) return 0.0;

   MqlRates ratesDia[];
   ArraySetAsSeries(ratesDia, true);
   int total = CopyRates(CodigoAtivo, PERIOD_CURRENT, inicioDia, ultimaBarra, ratesDia);
   if(total <= 0) return 0.0;

   double somaPV = 0.0, somaV = 0.0;
   for(int i = 0; i < total; i++)
   {
      double preco = (ratesDia[i].high + ratesDia[i].low + ratesDia[i].close) / 3.0;
      double vol   = (double)ratesDia[i].tick_volume;
      somaPV += preco * vol;
      somaV  += vol;
   }
   return (somaV > 0.0) ? somaPV / somaV : 0.0;
}

//+------------------------------------------------------------------+
//| CruzamentoEMA20_50  [Modulo 14] - M1                             |
//+------------------------------------------------------------------+
int CruzamentoEMA20_50()
{
   double bufEMA20[2], bufEMA50[2];
   if(CopyBuffer(g_handleEMA20, 0, 1, 2, bufEMA20) < 2) return 0;
   if(CopyBuffer(g_handleEMA50, 0, 1, 2, bufEMA50) < 2) return 0;

   // [1]=2 barras atras (prev), [0]=1 barra atras (now)
   if(bufEMA20[1] <= bufEMA50[1] && bufEMA20[0] > bufEMA50[0]) return  1;
   if(bufEMA20[1] >= bufEMA50[1] && bufEMA20[0] < bufEMA50[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| TendenciaM3  [Modulo 15]                                         |
//+------------------------------------------------------------------+
int TendenciaM3()
{
   if(g_ema20_M3 <= 0.0 || g_ema50_M3 <= 0.0) return 0;
   if(g_ema20_M3 > g_ema50_M3) { if(LogTendencia) Print("[Tendencia M3] Alta");  return  1; }
   if(g_ema20_M3 < g_ema50_M3) { if(LogTendencia) Print("[Tendencia M3] Baixa"); return -1; }
   return 0;
}

//+------------------------------------------------------------------+
//| TendenciaM5  [Modulo 16]                                         |
//+------------------------------------------------------------------+
int TendenciaM5()
{
   if(g_ema20_M5 <= 0.0 || g_ema50_M5 <= 0.0) return 0;
   if(g_ema20_M5 > g_ema50_M5) { if(LogTendencia) Print("[Tendencia M5] Alta");  return  1; }
   if(g_ema20_M5 < g_ema50_M5) { if(LogTendencia) Print("[Tendencia M5] Baixa"); return -1; }
   return 0;
}

//+------------------------------------------------------------------+
//| DivergenciaRSI  [Modulo 17]                                      |
//| FIX #2: usa g_rsiPrev (global) atualizado antes de AtualizarDados|
//+------------------------------------------------------------------+
int DivergenciaRSI()
{
   if(ArraySize(g_rates) < 6) return 0;
   if(g_rsiPrev <= 0.0)       return 0; // sem dado anterior ainda

   double precoAtual = g_rates[0].close;
   double precoAnt   = g_rates[5].close;

   // Divergencia bullish: preco faz minimo mais baixo, RSI faz minimo mais alto
   if(precoAtual < precoAnt && g_rsi > g_rsiPrev) return  1;

   // Divergencia bearish: preco faz maximo mais alto, RSI faz maximo mais baixo
   if(precoAtual > precoAnt && g_rsi < g_rsiPrev) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| RejeicaoWick  [Modulo 18]                                        |
//+------------------------------------------------------------------+
int RejeicaoWick()
{
   if(ArraySize(g_rates) < 1) return 0;

   double corpo      = MathAbs(g_rates[0].close - g_rates[0].open);
   double upperWick  = g_rates[0].high - MathMax(g_rates[0].open, g_rates[0].close);
   double lowerWick  = MathMin(g_rates[0].open, g_rates[0].close) - g_rates[0].low;

   if(corpo <= 0.0) return 0;

   if(upperWick > corpo * 2.0) return -1; // rejeicao de topo -> venda
   if(lowerWick > corpo * 2.0) return  1; // rejeicao de fundo -> compra
   return 0;
}

//+------------------------------------------------------------------+
//| Engolfo  [Modulo 19]                                             |
//+------------------------------------------------------------------+
int Engolfo()
{
   if(ArraySize(g_rates) < 2) return 0;

   bool candleAtualAlta    = g_rates[0].close > g_rates[0].open;
   bool candleAnteriorBaixa = g_rates[1].close < g_rates[1].open;
   bool candleAtualBaixa   = g_rates[0].close < g_rates[0].open;
   bool candleAnteriorAlta  = g_rates[1].close > g_rates[1].open;

   // Engolfo bullish
   if(candleAtualAlta && candleAnteriorBaixa &&
      g_rates[0].close > g_rates[1].open &&
      g_rates[0].open  < g_rates[1].close)
      return 1;

   // Engolfo bearish
   if(candleAtualBaixa && candleAnteriorAlta &&
      g_rates[0].close < g_rates[1].open &&
      g_rates[0].open  > g_rates[1].close)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| RegimaMercado  [Modulo 20]                                             |
//+------------------------------------------------------------------+

int RegimeMercado()
{
   double ema20[], ema50[];

   if(CopyBuffer(g_handleEMA20,0,0,1,ema20) < 1)
      return 0;

   if(CopyBuffer(g_handleEMA50,0,0,1,ema50) < 1)
      return 0;

   double ponto = SymbolInfoDouble(CodigoAtivo,SYMBOL_POINT);

   double distancia = MathAbs(ema20[0] - ema50[0]) / ponto;

   if(distancia < DistanciaMinimaEMAs)
      return 2; // consolidação

   return 1; // tendência
}

//==================================================================//
//  SECAO 14B - FUNCOES AUXILIARES DE REGIME                        //
//==================================================================//

bool MercadoLateral()
{
   return (MathAbs(g_ema20 - g_ema50) < DistanciaMinimaEMAs * _Point);
}

bool MercadoTendencialForte()
{
   return (g_ema20 > g_ema50 && g_ema50 > g_ema72) ||
          (g_ema20 < g_ema50 && g_ema50 < g_ema72);
}

//+------------------------------------------------------------------+
//| DetectarRegime                                                   |
//| FIX #3: resultado cacheado em g_regime, LimpezaLiquidez()        |
//|         chamada apenas uma vez por barra                         |
//+------------------------------------------------------------------+
int DetectarRegime()
{
   bool tendenciaForte = MercadoTendencialForte();
   bool lateral        = MercadoLateral();

   // Usa o resultado ja calculado no cache de g_rates
   int  liquidez  = LimpezaLiquidez();
   bool sweep     = (liquidez != 0);
   bool expansao  = CandleDisplacement();

   if(sweep && expansao) return 3; // Manipulacao (smart money entry)
   if(tendenciaForte)    return 1; // Tendencia forte
   if(lateral)           return 2; // Lateral / range
   return 0;                       // Indefinido
}

//==================================================================//
//  SECAO 14C - FUNCOES DE CONFIRMACAO DE ENTRADA                   //
//==================================================================//

bool BreakoutAlta()
{
   if(ArraySize(g_rates) < 20) return false;
   double maxRef = g_rates[1].high;
   for(int i = 2; i < 20; i++)
      if(g_rates[i].high > maxRef) maxRef = g_rates[i].high;
   return (g_rates[0].close > maxRef && g_rates[0].close > g_ema72);
}

bool BreakoutBaixa()
{
   if(ArraySize(g_rates) < 20) return false;
   double minRef = g_rates[1].low;
   for(int i = 2; i < 20; i++)
      if(g_rates[i].low < minRef) minRef = g_rates[i].low;
   return (g_rates[0].close < minRef && g_rates[0].close < g_ema72);
}

bool CandleDisplacement()
{
   if(ArraySize(g_rates) < 2) return false;
   double corpo         = MathAbs(g_rates[0].close - g_rates[0].open);
   double corpoAnterior = MathAbs(g_rates[1].close - g_rates[1].open);
   return (corpoAnterior > 0.0 && corpo > corpoAnterior * 1.5);
}

//==================================================================//
//  SECAO 15 - CAMADA 3 & 4: SISTEMA DE SCORE PONDERADO             //
//  FIX #4: multiplicadores de regime removidos (inflavam score)    //
//  FIX #5: ReversaoValida movida para fora de CalcularScore()      //
//  FIX #10: pesos dos modulos de reversao agora sao inputs         //
//==================================================================//

//+------------------------------------------------------------------+
//| ReversaoValida                                                   |
//| FIX #5: funcao declarada antes de CalcularScore(), nao dentro   |
//+------------------------------------------------------------------+
bool ReversaoValida()
{
   int scoreRev = MathAbs(Engolfo()) + MathAbs(RejeicaoWick()) + MathAbs(DivergenciaRSI());
   return (scoreRev >= 2);
}

int CalcularScore()
{
   int score = 0, resultado = 0;
   bool lateral = MercadoLateral();

   // === MODULOS DE TENDENCIA E ESTRUTURA ===
   if(UsePivotRSI)      { resultado = PivotRSI();           score += resultado * PesoRSI;         }
   if(UseEstocastico)   { resultado = Estocastico();        score += resultado * PesoEstocastico;  }
   if(UseLiquidez)      { resultado = LimpezaLiquidez();    score += resultado * PesoLiquidez;     }
   if(UseTendencia)     { resultado = Tendencia();          score += resultado * PesoTendencia;    }
   if(UseContinuidade)  { resultado = Continuidade();       score += resultado * PesoContinuidade; }
   if(UseEstrutura)     { resultado = EstruturaMercado();   score += resultado * PesoEstrutura;    }
   if(UseCHOCH)         { resultado = DetectarCHOCH();      score += resultado * PesoCHOCH;        }
   if(UseBOS)           { resultado = DetectarBOS();        score += resultado * PesoBOS;          }
   if(UseFVG)           { resultado = DetectarFVG();        score += resultado * PesoFVG;          }
   if(UseOrderBlock)    { resultado = DetectarOrderBlock(); score += resultado * PesoOrderBlock;   }
   if(UseForcaCandle)   { resultado = ForcaCandle();        score += resultado * PesoCandle;       }
   if(UseVWAP)          { resultado = ModuloVWAP();         score += resultado * PesoVWAP;         }
   if(UseCruzamentoEMA) { resultado = CruzamentoEMA20_50(); score += resultado * PesoEMA;          }
   if(UseTendenciaM3)   { resultado = TendenciaM3();        score += resultado * PesoTendenciaM3;  }
   if(UseTendenciaM5)   { resultado = TendenciaM5();        score += resultado * PesoTendenciaM5;  }

   // === MODULOS DE REVERSAO (ativos em mercado lateral ou manipulacao) ===
   // Aplicados com peso maior em lateralizacao (regime 2)
   int pesoContexto = lateral ? 2 : 1;

   if(UseDivergenciaRSI) { resultado = DivergenciaRSI(); score += resultado * (PesoDivergenciaRSI * pesoContexto); }
   if(UseRejeicaoWick)   { resultado = RejeicaoWick();   score += resultado * (PesoRejeicaoWick   * pesoContexto); }
   if(UseEngolfo)        { resultado = Engolfo();        score += resultado * (PesoEngolfo        * pesoContexto); }

   return score;
}

//==================================================================//
//  SECAO 16 - EXECUCAO PRINCIPAL                                   //
//==================================================================//
void ExecutarEstrategia()

{   
   // === MODO DE VALIDACAO ===
   if(ValidationMode)
   {
      int resultado = ObterResultadoValidacao(ValidationNumber);
      if(resultado > 0) { AbrirOperacao(DIRECAO_COMPRA); Print("[VALIDACAO] Modulo ", ValidationNumber, " -> COMPRA"); }
      if(resultado < 0) { AbrirOperacao(DIRECAO_VENDA);  Print("[VALIDACAO] Modulo ", ValidationNumber, " -> VENDA");  }
      return;
   }

   // === FILTROS GERAIS ===
   if(TemPosicao())                 return;
   if(!DentroDoHorario())           return;
   if(!SessaoPermitida())           return;
   if(!FiltroSpread())              return;
   if(!FiltroATR())                 return;
   if(!FiltroDistanciaEMAs())       return;
   if(!FiltroDistanciaPrecoEMA72()) return;
   if(!CooldownOk())                return;
   if(!CandleNaoOperado())          return;
   if(!FiltroInclinacaoEMA())       return;

   if(LimiteOperacoesDia()) { Print("[ROBO] Limite de operacoes do dia atingido."); return; }
   if(StopDiarioAtingido()) { Print("[ROBO] Stop diario atingido.");                return; }
   if(MetaDiariaAtingida()) { Print("[ROBO] Meta diaria atingida.");                return; }
   if(StopsConsecutivos())  { Print("[ROBO] Max stops consecutivos atingido.");     return; }
   if(WinsConsecutivos())   { Print("[ROBO] Max wins consecutivos atingido.");      return; }

   // === DADOS DE CONFIRMACAO ===
   double precoAtual    = g_rates[0].close;
   bool   breakoutAlta  = BreakoutAlta();
   bool   breakoutBaixa = BreakoutBaixa();
   bool   impulso       = CandleDisplacement();
   bool   lateral       = MercadoLateral();
   int    sinalRev      = Engolfo() + RejeicaoWick() + DivergenciaRSI();

// ======================================================
// COMPRA
// ======================================================
   if(g_scoreFinal >= ScoreMinimoCompra)
   {
   // REGIME 3 = MANIPULACAO
   if(g_regime == 3 && breakoutAlta && impulso)
   {
      if(LogEntrada)
         Print("[ENTRADA] COMPRA (MANIPULACAO) | Score=", g_scoreFinal);

      AbrirOperacao(DIRECAO_COMPRA);
      return;
   }

   // REGIME 1 = TENDENCIA
   if(g_regime == 1 && !lateral)
   {
      if(LogEntrada)
         Print("[ENTRADA] COMPRA (TENDENCIA) | Score=", g_scoreFinal);

      AbrirOperacao(DIRECAO_COMPRA);
      return;
   }

   // REGIME 2 = RANGE
   if(g_regime == 2 && lateral && sinalRev > 0 && ReversaoValida())
   {
      if(LogEntrada)
         Print("[ENTRADA] COMPRA (RANGE) | Score=", g_scoreFinal);

      AbrirOperacao(DIRECAO_COMPRA);
      return;
   }
   }

// ======================================================
// VENDA
// ======================================================
   if(g_scoreFinal <= ScoreMinimoVenda)
   {
   // REGIME 3 = MANIPULACAO
   if(g_regime == 3 && breakoutBaixa && impulso)
   {
      if(LogEntrada)
         Print("[ENTRADA] VENDA (MANIPULACAO) | Score=", g_scoreFinal);

      AbrirOperacao(DIRECAO_VENDA);
      return;
   }

   // REGIME 1 = TENDENCIA
   if(g_regime == 1 && !lateral)
   {
      if(LogEntrada)
         Print("[ENTRADA] VENDA (TENDENCIA) | Score=", g_scoreFinal);

      AbrirOperacao(DIRECAO_VENDA);
      return;
   }

   // REGIME 2 = RANGE
   if(g_regime == 2 && lateral && sinalRev < 0 && ReversaoValida())
   {
      if(LogEntrada)
         Print("[ENTRADA] VENDA (RANGE) | Score=", g_scoreFinal);

      AbrirOperacao(DIRECAO_VENDA);
      return;
   }
 }
}

int ObterResultadoValidacao(int numero)
{
   switch(numero)
   {
      case  1: return PivotRSI();
      case  2: return LimpezaLiquidez();
      case  3: return Tendencia();
      case  4: return Continuidade();
      case  5: return EstruturaMercado();
      case  6: return DetectarCHOCH();
      case  7: return DetectarBOS();
      case  8: return DetectarFVG();
      case  9: return DetectarOrderBlock();
      case 10: return ForcaCandle();
      case 11: return Estocastico();
      case 12: return ModuloVWAP();
      case 13: return CruzamentoEMA20_50();
      case 14: return TendenciaM3();
      case 15: return TendenciaM5();
      case 16: return DivergenciaRSI();
      case 17: return RejeicaoWick();
      case 18: return Engolfo();
      default: return 0;
   }
}
//==================================================================//
//  SECAO 17 - GESTAO DA POSICAO ABERTA (tick a tick)              //
//==================================================================//

void GerenciarPosicaoAberta()
{
   ulong ticket;
   if(!SelecionarPosicao(ticket))      return;
   if(!PositionSelectByTicket(ticket)) return;

   ENUM_POSITION_TYPE tipo    = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   ENUM_DIRECAO       direcao = (tipo == POSITION_TYPE_BUY) ? DIRECAO_COMPRA : DIRECAO_VENDA;

   double precoEntrada = PositionGetDouble(POSITION_PRICE_OPEN);
   double slAtual      = PositionGetDouble(POSITION_SL);
   double ponto        = SymbolInfoDouble(CodigoAtivo, SYMBOL_POINT);
   int    digitos      = (int)SymbolInfoInteger(CodigoAtivo, SYMBOL_DIGITS);
   double R            = StopInicialPontos * ponto;

   double precoAtual = (tipo == POSITION_TYPE_BUY)
                        ? SymbolInfoDouble(CodigoAtivo, SYMBOL_BID)
                        : SymbolInfoDouble(CodigoAtivo, SYMBOL_ASK);

   double lucroEmPreco = (direcao == DIRECAO_COMPRA)
                         ? (precoAtual - precoEntrada)
                         : (precoEntrada - precoAtual);
   double lucroEmR = lucroEmPreco / R;

   // =========================================================
   // TRAILING ATIVO: atualiza a cada tick
   // =========================================================
   if(g_estagio3Ativado)
   {
      double novoSL = (direcao == DIRECAO_COMPRA)
                      ? NormalizeDouble(precoAtual - (3.0 * R), digitos)
                      : NormalizeDouble(precoAtual + (3.0 * R), digitos);

      bool slMelhorou = (tipo == POSITION_TYPE_BUY)
                        ? (novoSL > slAtual + ponto)
                        : (novoSL < slAtual - ponto);

      if(slMelhorou)
      {
         if(LogGestao) Print("[GESTAO] Trailing 3R atualizado | SL=", novoSL, " | LucroR=", DoubleToString(lucroEmR, 2));
         g_trade.PositionModify(ticket, novoSL, 0.0);
      }
      return;
   }

   // =========================================================
   // ESTAGIO 3: 6R atingido -> ativa trailing de 3R
   // =========================================================
   if(lucroEmR >= 6.0 && !g_estagio3Ativado)
   {
      double novoSL = (direcao == DIRECAO_COMPRA)
                      ? NormalizeDouble(precoAtual - (3.0 * R), digitos)
                      : NormalizeDouble(precoAtual + (3.0 * R), digitos);

      bool slMelhorou = (tipo == POSITION_TYPE_BUY)
                        ? (novoSL > slAtual + ponto)
                        : (slAtual == 0.0 || novoSL < slAtual - ponto);

      if(slMelhorou) g_trade.PositionModify(ticket, novoSL, 0.0);

      g_estagio1Ativado = true;
      g_estagio2Ativado = true;
      g_estagio3Ativado = true;

      if(LogGestao) Print("[GESTAO] Estagio 3 ativo: Trailing 3R | SL=", novoSL, " | LucroR=", DoubleToString(lucroEmR, 2));
      return;
   }

   // =========================================================
   // ESTAGIO 2: 4R atingido -> SL em 1.0R
   // FIX #9: log corrigido (dizia "1.5R" mas move para "1.0R")
   // =========================================================
   if(lucroEmR >= 4.0 && !g_estagio2Ativado)
   {
      double novoSL = (direcao == DIRECAO_COMPRA)
                      ? NormalizeDouble(precoEntrada + (1.0 * R), digitos)
                      : NormalizeDouble(precoEntrada - (1.0 * R), digitos);

      bool slMelhorou = (tipo == POSITION_TYPE_BUY)
                        ? (novoSL > slAtual + ponto)
                        : (slAtual == 0.0 || novoSL < slAtual - ponto);

      if(slMelhorou) g_trade.PositionModify(ticket, novoSL, 0.0);

      g_estagio1Ativado = true;
      g_estagio2Ativado = true;

      if(LogGestao) Print("[GESTAO] Estagio 2 ativo: SL em 1.0R | SL=", novoSL);
      return;
   }

   // =========================================================
   // ESTAGIO 1: 2.0R atingido -> Break Even
   // =========================================================
   if(lucroEmR >= 2.0 && !g_estagio1Ativado)
   {
      double novoSL = NormalizeDouble(precoEntrada, digitos);

      bool slMelhorou = (tipo == POSITION_TYPE_BUY)
                        ? (novoSL > slAtual + ponto)
                        : (slAtual == 0.0 || novoSL < slAtual - ponto);

      if(slMelhorou) g_trade.PositionModify(ticket, novoSL, 0.0);

      g_estagio1Ativado = true;

      if(LogGestao) Print("[GESTAO] Estagio 1 ativo: Break Even | SL=", novoSL);
   }
}

//==================================================================//
//  SECAO 18 - ABERTURA DE OPERACAO                                  //
//==================================================================//

void AbrirOperacao(const ENUM_DIRECAO direcao)
{
   if(!FiltroSpread()) return;

   double volume  = CalcularVolume();
   int    digitos = (int)SymbolInfoInteger(CodigoAtivo, SYMBOL_DIGITS);
   double ponto   = SymbolInfoDouble(CodigoAtivo, SYMBOL_POINT);
   double distSL  = StopInicialPontos * ponto;

   g_estagio1Ativado = false;
   g_estagio2Ativado = false;
   g_estagio3Ativado = false;

   if(direcao == DIRECAO_COMPRA)
   {
      double preco = SymbolInfoDouble(CodigoAtivo, SYMBOL_ASK);
      double sl    = NormalizeDouble(preco - distSL, digitos);
      if(!g_trade.Buy(volume, CodigoAtivo, preco, sl, 0.0, "MetaOp2-C"))
         Print("[AbrirOperacao] Falha COMPRA: ", g_trade.ResultRetcodeDescription());
      else
      {
         g_ultimoCandleOperado = iTime(CodigoAtivo, PERIOD_CURRENT, 0);
         if(LogEntrada) Print("[AbrirOperacao] COMPRA | Vol=", volume, " | SL=", sl,
                              " | 1R=", StopInicialPontos, "pts | Score=", g_scoreFinal);
      }
   }
   else
   {
      double preco = SymbolInfoDouble(CodigoAtivo, SYMBOL_BID);
      double sl    = NormalizeDouble(preco + distSL, digitos);
      if(!g_trade.Sell(volume, CodigoAtivo, preco, sl, 0.0, "MetaOp2-V"))
         Print("[AbrirOperacao] Falha VENDA: ", g_trade.ResultRetcodeDescription());
      else
      {
         g_ultimoCandleOperado = iTime(CodigoAtivo, PERIOD_CURRENT, 0);
         if(LogEntrada) Print("[AbrirOperacao] VENDA | Vol=", volume, " | SL=", sl,
                              " | 1R=", StopInicialPontos, "pts | Score=", g_scoreFinal);
      }
   }
}

double CalcularVolume()
{
   double volume = LoteFixo;
   if(UseRiskPercent && RiskPercent > 0.0)
   {
      double saldo     = AccountInfoDouble(ACCOUNT_BALANCE);
      double risco     = saldo * (RiskPercent / 100.0);
      double ponto     = SymbolInfoDouble(CodigoAtivo, SYMBOL_POINT);
      double tickValue = SymbolInfoDouble(CodigoAtivo, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(CodigoAtivo, SYMBOL_TRADE_TICK_SIZE);
      double distSL    = StopInicialPontos * ponto;
      if(tickValue > 0.0 && tickSize > 0.0 && distSL > 0.0)
      {
         double valorPorLote = (tickValue / tickSize) * distSL;
         if(valorPorLote > 0.0) volume = risco / valorPorLote;
      }
   }
   return ValidarVolume(volume);
}

double ValidarVolume(const double vol)
{
   double minVol = SymbolInfoDouble(CodigoAtivo, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(CodigoAtivo, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(CodigoAtivo, SYMBOL_VOLUME_STEP);
   double v = vol;
   if(v < minVol) v = minVol;
   if(v > maxVol) v = maxVol;
   if(step > 0.0) v = MathRound(v / step) * step;
   return NormalizeDouble(v, 2);
}

void FecharPosicao(const string motivo)
{
   if(!g_trade.PositionClose(CodigoAtivo))
      Print("[FecharPosicao] Falha (", motivo, "): ", g_trade.ResultRetcodeDescription());
   else
      if(LogSaida) Print("[FecharPosicao] Encerrada. Motivo: ", motivo);
}

//==================================================================//
//  SECAO 19 - FILTROS E VERIFICACOES                               //
//==================================================================//

bool FiltroSpread()
{
   if(MaxSpread <= 0) return true;
   return (g_spreadAtual <= (double)MaxSpread);
}

bool FiltroATR()
{
   if(ATRMinimo <= 0.0) return true;
   return (g_atr >= ATRMinimo * _Point);
}

bool FiltroInclinacaoEMA()
{
   double bufAnterior[1];
   if(CopyBuffer(g_handleEMA20, 0, 2, 1, bufAnterior) < 1) return false;
   return (MathAbs(g_ema20 - bufAnterior[0]) > EMA20_MinSlopePoints * _Point);
}

bool FiltroDistanciaEMAs()
{
   return (MathAbs(g_ema20 - g_ema72) > DistanciaMinimaEMAs * _Point);
}

bool FiltroDistanciaPrecoEMA72()
{
   if(ArraySize(g_rates) < 1) return false;
   return (MathAbs(g_rates[0].close - g_ema72) > DistanciaMinimaEMA72 * _Point);
}

bool CandleNaoOperado()
{
   return (iTime(CodigoAtivo, PERIOD_CURRENT, 0) != g_ultimoCandleOperado);
}

bool CooldownOk()
{
   return (g_candlesCooldown <= 0);
}

bool DentroDoHorario()
{
   int      offsetSeg = (GMTOffsetBrasil - GMTOffsetBroker) * 3600;
   datetime horaLocal = TimeCurrent() + offsetSeg;
   MqlDateTime agora;
   TimeToStruct(horaLocal, agora);
   int segAgora = agora.hour * 3600 + agora.min * 60 + agora.sec;

   if(HoraInicioExecucao > 0)
   {
      MqlDateTime ini; TimeToStruct(HoraInicioExecucao, ini);
      if(segAgora < ini.hour * 3600 + ini.min * 60 + ini.sec) return false;
   }
   if(HoraFimExecucao > 0)
   {
      MqlDateTime fim; TimeToStruct(HoraFimExecucao, fim);
      if(segAgora > fim.hour * 3600 + fim.min * 60 + fim.sec) return false;
   }
   return true;
}

bool SessaoPermitida()
{
   if(!OperarAsia && !OperarLondres && !OperarNovaYork) return true;

   int      offsetSeg = (GMTOffsetBrasil - GMTOffsetBroker) * 3600;
   datetime horaLocal = TimeCurrent() + offsetSeg;
   MqlDateTime agora;
   TimeToStruct(horaLocal, agora);
   int h = agora.hour;

   if(OperarAsia     && h >= 0  && h < 8)  return true;
   if(OperarLondres  && h >= 8  && h < 12) return true;
   if(OperarNovaYork && h >= 12 && h < 20) return true;
   return false;
}

bool LimiteOperacoesDia() { return (MaxOperacoesDia  > 0   && g_operacoesDia  >= MaxOperacoesDia);  }
bool StopDiarioAtingido() { return (MaxStopDia       > 0.0 && g_resultadoDia  <= -MaxStopDia);      }
bool MetaDiariaAtingida() { return (MaxMetaDia       > 0.0 && g_resultadoDia  >= MaxMetaDia);       }
bool StopsConsecutivos()  { return (MaxStopsSeguidos > 0   && g_stopsSeguidos >= MaxStopsSeguidos); }
bool WinsConsecutivos()   { return (MaxWinsSeguidos  > 0   && g_winsSeguidos  >= MaxWinsSeguidos);  }

//==================================================================//
//  SECAO 20 - CONTROLE DE POSICAO                                   //
//==================================================================//

bool TemPosicao()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL)       == CodigoAtivo &&
            (long)PositionGetInteger(POSITION_MAGIC) == (long)MagicId)
            return true;
   }
   return false;
}

bool SelecionarPosicao(ulong &ticket_out)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL)       == CodigoAtivo &&
            (long)PositionGetInteger(POSITION_MAGIC) == (long)MagicId)
         {
            ticket_out = ticket;
            return true;
         }
   }
   return false;
}

//==================================================================//
//  SECAO 21 - ESTATISTICAS DO DIA                                   //
//==================================================================//

void AtualizarEstatisticasDia()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime inicioDia = StructToTime(dt);

   double resultado = 0.0;
   int    contador  = 0, winsSeq = 0, stopsSeq = 0;
   double ultimoRes = 0.0;

   if(HistorySelect(inicioDia, TimeCurrent()))
   {
      int totalDeals = HistoryDealsTotal();
      for(int i = 0; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL)       != CodigoAtivo) continue;
         if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)MagicId) continue;

         double lucro = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                      + HistoryDealGetDouble(ticket, DEAL_SWAP)
                      + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         resultado += lucro;

         ENUM_DEAL_ENTRY entrada = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entrada == DEAL_ENTRY_OUT)
         {
            if(lucro > 0.0) { winsSeq++;  stopsSeq = 0; }
            else            { stopsSeq++; winsSeq  = 0; }
            ultimoRes = lucro;
         }
         if(entrada == DEAL_ENTRY_IN) contador++;
      }
   }
   else
      Print("[AtualizarEstatisticasDia] Falha ao selecionar historico. Codigo: ", GetLastError());

   if(g_candlesCooldown > 0) g_candlesCooldown--;
   if(ultimoRes < 0.0 && ultimoRes != g_ultimoResultado) g_candlesCooldown = CooldownCandles;

   g_ultimoResultado = ultimoRes;
   g_resultadoDia    = resultado;
   g_operacoesDia    = contador;
   g_stopsSeguidos   = stopsSeq;
   g_winsSeguidos    = winsSeq;
}

//==================================================================//
//  SECAO 22 - ESTATISTICAS FINAIS (backtest)                        //
//==================================================================//

void ExibirEstatisticasFinais()
{
   if(!HistorySelect(0, TimeCurrent())) return;

   int    totalTrades = 0, wins = 0, losses = 0;
   double grossWin = 0.0, grossLoss = 0.0, maxDD = 0.0, pico = 0.0, acumulado = 0.0;

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL)       != CodigoAtivo) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)MagicId) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double lucro = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                   + HistoryDealGetDouble(ticket, DEAL_SWAP)
                   + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      totalTrades++;
      acumulado += lucro;

      if(lucro > 0.0) { wins++;   grossWin  += lucro;          }
      else            { losses++; grossLoss += MathAbs(lucro); }

      if(acumulado > pico) pico = acumulado;
      double dd = pico - acumulado;
      if(dd > maxDD) maxDD = dd;
   }

   double winRate     = (totalTrades > 0) ? (double)wins / totalTrades * 100.0 : 0.0;
   double lossRate    = 100.0 - winRate;
   double profitFact  = (grossLoss > 0.0) ? grossWin / grossLoss : 0.0;
   double payoff      = (losses > 0 && wins > 0) ? (grossWin / wins) / (grossLoss / losses) : 0.0;
   double expectancia = (totalTrades > 0)
                        ? (winRate  / 100.0 * (wins   > 0 ? grossWin  / wins   : 0.0))
                        - (lossRate / 100.0 * (losses > 0 ? grossLoss / losses : 0.0))
                        : 0.0;

   Print("╔══════════════════════════════════════╗");
   Print("║   ESTATISTICAS FINAIS - MetaOp 2.05  ║");
   Print("╠══════════════════════════════════════════════════════════╣");
   Print("║ Total Trades    : ", totalTrades);
   Print("║ Win Rate        : ", DoubleToString(winRate,    2), "%");
   Print("║ Loss Rate       : ", DoubleToString(lossRate,   2), "%");
   Print("║ Profit Factor   : ", DoubleToString(profitFact, 3));
   Print("║ Payoff (RR med.): ", DoubleToString(payoff,     3));
   Print("║ Drawdown Max    : ", DoubleToString(maxDD,      2));
   Print("║ Lucro Liquido   : ", DoubleToString(acumulado,  2));
   Print("║ Expectancia Mat.: ", DoubleToString(expectancia,4));
   Print("╚══════════════════════════════════════╝");
}