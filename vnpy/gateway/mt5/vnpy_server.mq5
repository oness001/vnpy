#property copyright "vntech"
#property link      "vnpy.com"
#property version   "1.00"
#property strict

#include <Zmq/Zmq.mqh>
#include <JAson.mqh>

#define True true
#define False false

#define TimeToStr TimeToString
#define StrToTime StringToTime

#define FUNCTION_QUERYCONTRACT 0
#define FUNCTION_SUBSCRIBE 1
#define FUNCTION_SENDORDER 2
#define FUNCTION_CANCELORDER 3
#define FUNCTION_QUERYHISTORY 4

extern string HOSTNAME = "*";
extern int REP_PORT = 6888;
extern int PUB_PORT = 8666;
extern int MILLISECOND_TIMER = 10;

Context context("vnpy");
Socket rep_socket(context, ZMQ_REP);
Socket pub_socket(context, ZMQ_PUB);

string subscribed_symbols[100];
int subscribed_count;
int timer_count;

int OnInit()
{
   for (int i=0; i<100; ++i)
   {
      subscribed_symbols[i] = "";
   }
   
   timer_count = 0;
   
   EventSetMillisecondTimer(MILLISECOND_TIMER);
   context.setBlocky(false);

   rep_socket.bind(StringFormat("tcp://%s:%d", HOSTNAME, REP_PORT));
   pub_socket.bind(StringFormat("tcp://%s:%d", HOSTNAME, PUB_PORT));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   rep_socket.unbind(StringFormat("tcp://%s:%d", HOSTNAME, REP_PORT));
   rep_socket.disconnect(StringFormat("tcp://%s:%d", HOSTNAME, REP_PORT));
   
   pub_socket.unbind(StringFormat("tcp://%s:%d", HOSTNAME, PUB_PORT));
   pub_socket.disconnect(StringFormat("tcp://%s:%d", HOSTNAME, PUB_PORT));
   
   context.destroy(0);

   EventKillTimer();
}

void OnTick()
{

}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   CJAVal rep_json(NULL, jtUNDEF);
   rep_json["type"] = "on_order";
   
   rep_json["data"]["symbol"] = trans.symbol;
   rep_json["data"]["deal"] = (int)trans.deal;
   rep_json["data"]["order"] = (int) trans.order;
   rep_json["data"]["event_type"] = (int) (ENUM_TRADE_TRANSACTION_TYPE) trans.type;
   rep_json["data"]["order_type"] = (int) (ENUM_ORDER_TYPE) trans.order_type;
   rep_json["data"]["order_state"] = (int) (ENUM_ORDER_STATE) trans.order_state;
   rep_json["data"]["price"] = trans.price;
   rep_json["data"]["price_trigger"] = trans.price_trigger;
   rep_json["data"]["stop_loss"] = trans.price_sl;
   rep_json["data"]["take_profit"] = trans.price_tp;
   rep_json["data"]["volume"] = trans.volume;
   rep_json["data"]["position"] = (int) trans.position;
   rep_json["data"]["position_by"] = (int) trans.position_by;

   rep_json["data"]["magic"] = (int) request.magic;
   rep_json["data"]["order_"] = (int) request.order;   
   
   string rep_data = "";
   rep_json.Serialize(rep_data);

   ZmqMsg rep_msg(rep_data);
   pub_socket.send(rep_msg, true);
}

void OnTimer()
{
  //Publish data every 1 second
   timer_count += MILLISECOND_TIMER;
   
   if (timer_count >= 1000)
   {
      timer_count = 0;
      
      string price_data = get_price_info();
      ZmqMsg price_msg(price_data);
      pub_socket.send(price_msg, true);   
   
      string account_data = get_account_info();
      ZmqMsg account_msg(account_data);
      pub_socket.send(account_msg, true);   
      
   }
   
   //Process new request
   ZmqMsg req_msg;
   string req_data;
   CJAVal req_json(NULL, jtUNDEF);
   int req_type;
   
   rep_socket.recv(req_msg, true);
   if (req_msg.size() <= 0) return;
   
   req_data = req_msg.getData();
   req_json.Deserialize(req_data);
   req_type = req_json["type"].ToInt();
   
   string rep_data = "";
   switch(req_type)
   {
      case FUNCTION_QUERYCONTRACT:
         rep_data = get_contract_info();
         break;
         
      case FUNCTION_SUBSCRIBE:
         rep_data = subscribe(req_json);
         break;
         
      case FUNCTION_SENDORDER:
         rep_data = send_order(req_json);
         break;
      
      case FUNCTION_CANCELORDER:
         rep_data = cancel_order(req_json);
         break;
         
      case FUNCTION_QUERYHISTORY:
         rep_data = get_history_info(req_json);
         break;

   }
   
   ZmqMsg rep_msg(rep_data);
   rep_socket.send(rep_msg, true);   
}

string get_contract_info()
{
   CJAVal rep_json(NULL, jtUNDEF);
   string symbol;
   
   rep_json["type"] = "contract";
   
   int total_symbol = SymbolsTotal(False);
   for (int i=0; i<total_symbol; ++i)
   {
      symbol = SymbolName(i, False);
      rep_json["data"][i]["symbol"] = symbol;
      rep_json["data"][i]["digits"] = SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      rep_json["data"][i]["lot_size"] = SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      rep_json["data"][i]["min_lot"] = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   }
   
   string rep_data = "";
   rep_json.Serialize(rep_data); 
   return rep_data;
}

string get_account_info()
{
   CJAVal rep_json(NULL, jtUNDEF);
   
   rep_json["type"] = "account";
      
   rep_json["data"]["name"] = AccountInfoString(ACCOUNT_NAME);
   rep_json["data"]["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
   rep_json["data"]["margin"] = AccountInfoDouble(ACCOUNT_MARGIN);
   rep_json["data"]["free_margin"] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   rep_json["data"]["profit"] = AccountInfoDouble(ACCOUNT_PROFIT);
   rep_json["data"]["currency"] = AccountInfoString(ACCOUNT_CURRENCY);
   rep_json["data"]["company"] = AccountInfoString(ACCOUNT_COMPANY);
   
   string rep_data = "";
   rep_json.Serialize(rep_data); 
   return rep_data;
}

string get_price_info()
{
   CJAVal rep_json(NULL, jtUNDEF);
   string symbol;
   
   rep_json["type"] = "price";
   
   for (int i=0; i<100; ++i)
   {
      symbol = subscribed_symbols[i];
      
      if (symbol == "")
      {
         break;
      }
      
      rep_json["data"][i]["symbol"] = symbol;
      rep_json["data"][i]["bid_high"] = SymbolInfoDouble(symbol,SYMBOL_BIDHIGH);
      rep_json["data"][i]["ask_high"] = SymbolInfoDouble(symbol,SYMBOL_ASKHIGH);
      rep_json["data"][i]["last_high"] = SymbolInfoDouble(symbol,SYMBOL_LASTHIGH);
      rep_json["data"][i]["ask_low"] = SymbolInfoDouble(symbol,SYMBOL_ASKLOW);
      rep_json["data"][i]["bid_low"] = SymbolInfoDouble(symbol,SYMBOL_BIDLOW);
      rep_json["data"][i]["last_low"] = SymbolInfoDouble(symbol,SYMBOL_LASTLOW);     
      rep_json["data"][i]["time"] = SymbolInfoInteger(symbol,SYMBOL_TIME);
      rep_json["data"][i]["last"] = SymbolInfoDouble(symbol,SYMBOL_LAST);
      rep_json["data"][i]["bid"] = SymbolInfoDouble(symbol,SYMBOL_BID);
      rep_json["data"][i]["ask"] = SymbolInfoDouble(symbol,SYMBOL_ASK); 
      rep_json["data"][i]["last_volume"] = SymbolInfoDouble(symbol,SYMBOL_VOLUME_REAL);  

   }
  
   string rep_data = "";
   rep_json.Serialize(rep_data); 
   return rep_data;
}

string send_order(CJAVal &req_json)
{
   CJAVal rep_json(NULL, jtUNDEF);
  
   MqlTradeRequest request={0}; 
   
   int cmd = req_json["cmd"].ToInt();
   request.action=TRADE_ACTION_PENDING;        
   request.symbol=req_json["symbol"].ToStr();                     
   request.volume=req_json["volume"].ToDbl();                    
   request.sl=0;                                
   request.tp=0;                             
   request.type=(ENUM_ORDER_TYPE)cmd;               
   request.price=req_json["price"].ToDbl();
   request.magic = req_json["magic"].ToInt();

   MqlTradeResult result={0}; 

   bool n = OrderSendAsync(request,result); 
   
   int retcode = result.retcode;
   int order_id = result.order;
   int trade_id = result.deal;
   int request_id = result.request_id;
   int retcode_external = result.retcode_external;
   
   rep_json["type"] = "send";
   rep_json["data"]["result"] = n;
   
   string rep_data = "";
   rep_json.Serialize(rep_data); 
   return rep_data;
}

string cancel_order(CJAVal &req_json)
{
   CJAVal rep_json(NULL, jtUNDEF);
   string symbol;
   
   int ticket = req_json["ticket"].ToInt();
   bool result = OrderDelete(ticket);
   
   rep_json["type"] = "cancel";
   rep_json["data"]["result"] = result;
   
   string rep_data = "";
   rep_json.Serialize(rep_data); 
   return rep_data;
}
 
string subscribe(CJAVal &req_json)
{
   CJAVal rep_json(NULL, jtUNDEF);
    
   string symbol = req_json["symbol"].ToStr();
   bool new_symbol = true;
      
   for (int i=0; i<100; ++i)
   {
      if (subscribed_symbols[i] == "")
      {
         break;
      }
      
      if (subscribed_symbols[i] == symbol) 
      {
         new_symbol = false;
         break;
      }
   }
   
   if (new_symbol == true)
   {
      subscribed_symbols[subscribed_count]= symbol;
      subscribed_count += 1;
   }
    
   rep_json["type"] = "subscribe";
   rep_json["data"]["new_symbol"] = new_symbol;
   
   string rep_data = "";
   rep_json.Serialize(rep_data); 
   return rep_data;
}

bool OrderDelete(const ulong ticket)
  {
   MqlTradeRequest request = {0};
   request.action    =TRADE_ACTION_REMOVE;
   request.order     =ticket;
   
   MqlTradeResult result={0}; 

   return(OrderSendAsync(request,result));
  }
  
string get_history_info(CJAVal &req_json)
{
   CJAVal rep_json(NULL, jtUNDEF);
    
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   
   int copied=CopyRates(
      req_json["symbol"].ToStr(),
      (ENUM_TIMEFRAMES) req_json["interval"].ToInt(),
      StrToTime(req_json["start_time"].ToStr()),
      StrToTime(req_json["end_time"].ToStr()),
      rates
   );
   if(copied>0)
     {
      int size=fmin(copied,ArraySize(rates));
      for(int i=0;i<size;i++)
        {
         rep_json["type"] = "history";
         rep_json["result"] = 1;
         rep_json["data"][i]["time"] = TimeToStr(rates[i].time);
         rep_json["data"][i]["open"] = rates[i].open;
         rep_json["data"][i]["high"] = rates[i].high;
         rep_json["data"][i]["low"] = rates[i].low;
         rep_json["data"][i]["close"] = rates[i].close;
         rep_json["data"][i]["real_volume"] = rates[i].real_volume;
        }
     }
   else
       {
         rep_json["type"] = "history";
         rep_json["result"] = -1;
       }   
        
   string rep_data = "";
   rep_json.Serialize(rep_data); 
   return rep_data;
}