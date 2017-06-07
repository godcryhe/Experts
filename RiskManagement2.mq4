//+------------------------------------------------------------------+
//|                                               RiskManagement.mq4 |
//|                        Copyright 2017, MetaQuotes Software Corp. |
//|                                     zhixiang.zhang2011@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2017, MetaQuotes Software Corp."
#property link      "zhixiang.zhang2011@gmail.com"
#property version   "1.00"
#property strict

#include <stdlib.mqh>
#include <stderror.mqh>


//--- input parameters
input long     InitBalance = 10000; //risk per trade is based on the initial balance which is set at year start
input double   RiskPerTrade = 0.02; //risk per trade
input double   MaxRiskTotalTrade = 0.03;// max risk of total orders

input double   MaxWeeklyDrawDown = 0.04; //Max weekly drawdown
input double   MaxMonthlyDrawDown = 0.06;//Max monthly drawdown

input double   EmergencyStop = 0.1; //Stop trading for two weeks if 10% drawdown is reached
input double   MaxDrawDownAllowed = 0.2; //Max allowed drawdown

input int      StopTradingDaysOL = 5; // Min stop trading days because of loss is over risk limit

//input double   MaxProfitPerBreak = 0.25;//if profit reach 25%, 50%,75%,100%,125%,150%,175%,200%,225%,250%,275%,300% need to stop trading for 5 business days
//input int      MaxTradePerWeek = 3; //Max number of trading allowed per week

input double   MinLoss            = -10; //Min loss as a filter
input double   MinRRRatioPerTrade = 1.5; //Min RR ratio
input double   MinRRRatioHistory  = 1.8; //Min RR history ratio
input int      MinHisTradesToCalRRR = 5;  //the min number of transactions to calculate the RR ratio
input int      LastTradesToCalRRR   = 3;  //calculate the last 3-10 trades RR ratio

input int      StopTradingDaysRR  = 5;   //Min stop trading days because of history RR ratio < MinRRRatioHistory
 
input int      GMToffset = -6; //Mountain Daylight Time -6, Mountain time -7;
input int      ServerTimeGMToffset = 3; //server time and GMT offset

int TradingBeginHour = 0;
int TradingEndHour = 7;

int init_order_number = 0;
double max_risk_per_trade = InitBalance * RiskPerTrade; // max risk per trade
double max_risk_total_trade = InitBalance * MaxRiskTotalTrade;//total open positions max risk

int server_local_offset = ServerTimeGMToffset - GMToffset; //calculate the offset between server and local
int trading_allowed_begin_hour = TradingBeginHour + server_local_offset; // change local hour to server hour
int trading_allowed_end_hour   = TradingEndHour + server_local_offset; // change local hour to server hour

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {  
   
  }
  
double GetRiskMultiplier(string symbol)
  {
     double multiplier = 10;
     //Print(symbol);
     //commodities
     //XAU
     if(symbol == "XAUUSD")
       {
         multiplier = 1;
       }
     //XAG Symbol
     if(symbol == "XAGUSD")
       {
         multiplier = 50;         
       }  
     //XTI oil
     if(symbol == "XTIUSD")
       {
         multiplier = 1;                 
       }
     //Indices CFD,
     if(symbol == "US30" ||symbol == "US500" || symbol == "NAS100" || symbol == "JPN225"|| symbol == "GER30" )
       {
         multiplier = 0.1;         
       }   
     //Print(multiplier);     
     return multiplier;               
  }

/* The function returns point value for currency (symbol).
   Multiplies the point value for 10 for 3-5 digits brokers.*/
double XGetPoint( string symbol ) 
  {
     double point;
   
     point = MarketInfo( symbol, MODE_POINT );
     double digits = NormalizeDouble( MarketInfo( symbol, MODE_DIGITS ),0 );
   
     if( digits == 3 || digits == 5 ) {
        return(point*10.0);
     }
   
     return(point);
  }  

/*The function returns the risk value of open orders*/
double GetRiskperTrade(int ticket)
  {
    double risk = 0;
    double point = 0;
    string symbol;
    
    if( OrderSelect(ticket,SELECT_BY_TICKET) )
      { 
        symbol = OrderSymbol();
        point = XGetPoint(symbol);
        
        if( OrderType() == OP_BUY )
        { 
            risk = GetRiskMultiplier(symbol)* OrderLots() * ((OrderOpenPrice() - OrderStopLoss())/point);
            return risk;
        }
        
        if( OrderType() == OP_SELL )
        { 
            risk = GetRiskMultiplier(symbol)* OrderLots() * ((OrderStopLoss() - OrderOpenPrice())/point);
            return risk;
        }
          
        if( OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP )
        { 
            risk = GetRiskMultiplier(symbol)* OrderLots() * (MathAbs(OrderStopLoss() - OrderOpenPrice())/point);
            return risk;
        }    
      }
      
      return risk;
   }


/* the function returns the ticket of the last opened position*/
int GetLastOrderTicket()
  {
    int orders_total = OrdersTotal();
    int ticket = 0;
    datetime open_time = 0;
    
    for( int i = 0; i < orders_total; i++ )
    {
        if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) )
        {
           if( OrderOpenTime() > open_time )
           {     
             ticket = OrderTicket();
             open_time = OrderOpenTime();
           }           
        }
    }
    
    return(ticket);
 }

/* the function close the selected ticket of the last opened position*/

void CloseSelectOrder(int ticket)
  {
    if( OrderSelect(ticket,SELECT_BY_TICKET) )
      { 
        if( OrderType() == OP_BUY )
          if(OrderClose(ticket,OrderLots(),MarketInfo(OrderSymbol(),MODE_BID),30,Red)) 
            return;
        
        if( OrderType() == OP_SELL)  
          if(OrderClose(ticket,OrderLots(),MarketInfo(OrderSymbol(),MODE_ASK),30,Red)) 
            return;
          
        if( OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP )
          if( OrderDelete(ticket))
            return;         
      }
     return;  
  }

/* the function close all the limit orders*/
void DeleteAllLimitOrders()
  {
    for(int i = 0; OrdersTotal(); i++)
    {
      if( OrderSelect(i, MODE_TRADES) )
      {
        if( OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP )
        {  
          Print(OrderTicket());
          if( OrderDelete(OrderTicket()))        
            break;
        }
      }
    }
    
    return;
  }


/* the function close all the positions opened after trading hours allowed!*/
void  CloseAfterTradingHourOrders()
  {
    int open_hour = 0;
    
    for(int i = 0; OrdersTotal(); i++)
    {
      if( OrderSelect(i, MODE_TRADES) )
      {
        open_hour = TimeHour(OrderOpenTime());
        if( (open_hour < trading_allowed_begin_hour) || (open_hour > trading_allowed_end_hour) )//trading hour is not allowed, delete all limit orders and close any new orders.
          {
            CloseSelectOrder(OrderTicket());//need break to recalculate the order total because of the change of order total
            Print(OrderTicket());
            break;
          }
      }
    }
    
    return;
  }

   
/*
  The function is to check whether every order is with stoploss, if not close or delete this order
*/   
void CheckStopLossTakeProfit()
  {
    int total_order =  OrdersTotal();
    int order_ticket = 0;   
  
    for( int i = 0; i < total_order; i++ )
    {
        if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) )
        {
            order_ticket = OrderTicket();
                        
            // no stoploss, close open order
            if(( OrderStopLoss() == 0 )||( OrderTakeProfit() == 0 ))
            {
              //close order
              CloseSelectOrder(order_ticket);
              Print("Order was closed");
              Alert("No Stoploss or Take Profit! Order has been closed!");
              //push notification
              break;             
            }
            else
              continue; 
         }
     }
     //Print("Check stoploss finished!");
     return;             
  } 


/*
  The function is to check whether risk per trade is over 2%, if not close or delete this order
*/   
void CheckRiskperTrade()
  {
    int total_order =  OrdersTotal();
    int order_ticket = 0;
    double risk_per_trade = 0;    
    
    for( int i = 0; i < total_order; i++ )
    {
        if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) )
        {
            order_ticket = OrderTicket();         
            
            //to check Buy open positions whether risk is over 2%, trailing stoploss does not account
            risk_per_trade = GetRiskperTrade(order_ticket);
            //Print(risk_per_trade);
            if( risk_per_trade > max_risk_per_trade)
            {
              CloseSelectOrder(order_ticket);
              Alert("Risk per trade is over limit! order has been closed!");  
              //push notifications
              break; 
            }
            else 
             continue; 
        }          
     }
     //Print("Check Risk per trade finished!");
     return;             
  }     

/*
  The function is to check whether potential risk is over 4%, if not close or delete the lastest opening order
*/    
void CheckTotalTradeRisk() 
  {
    int total_order =  OrdersTotal();
    int order_ticket = 0;

    double risk_total_trade = 0;    
    
    for( int i = 0; i < total_order; i++ )
    {
        if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) )
        {
            order_ticket = OrderTicket();                      
            risk_total_trade += GetRiskperTrade(order_ticket);
            continue; 
         }                               
    }
    
    //Print(risk_total_trade);
    //if total open trade risk is over than limit 4%, close the latest open order
    if(risk_total_trade > max_risk_total_trade)
    {
      order_ticket = GetLastOrderTicket();
      CloseSelectOrder(order_ticket);
      Alert("Total opening risk is over limit! No new open order!");
    }
      
     //Print("Check total open order risk finished!");
     return;                 
    
  }

/*
  The function is to check whether reward risk ratio is more than minimum, if not close or delete the opening order
*/  
void   CheckRRRatio()
  {
    
    int total_order =  OrdersTotal();
    int order_ticket = 0;

    double ratio = 0;
    
    for( int i = 0; i < total_order; i++ )
    {
        if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) )
        {
            order_ticket = OrderTicket();                      
            if(GetRiskperTrade(order_ticket) <= 0) // stoploss has been set at least to open price and risk free
              continue; 
            else // calculate the RR ratio
            {
              ratio = MathAbs(OrderOpenPrice()-OrderTakeProfit())/MathAbs(OrderOpenPrice()-OrderStopLoss());
              if( ratio < MinRRRatioPerTrade ) //RR ratio < 1.5 close the order
                {
                  CloseSelectOrder(order_ticket);
                  Alert("Reward Risk ratio is less than min! Order is closed!");
                  break;
                }
              else
                continue;           
            }  
        }                               
    }  
    //Print(ratio);       
    //Print("Check RR ratio finished!");
    return;   
  }

/*
  The function is to check whether two loss happened in a row, if it does then stop trading for 5 business days.
*/  
void   CheckTwoLossInARow()
  {
     /*check last allow trading date, if the file is empty, write the current time in the file. 
       if the server time > allowed time, trading is allowed, else close all the open orders*/
     
     // trading allowed     
     int hst_total = OrdersHistoryTotal();

  }

/*
  The function is to check the limit order open time fall in the range between 11:55PM and 00:08AM(Mountain Time Zone)
  if not, delete all the limit orders.
*/  
void  CheckOrderOpenTime()
  {

     int order_open_hour = 0;
     
     //Print(trading_allowed_begin_hour);
     //Print(trading_allowed_end_hour);
     
     if( trading_allowed_begin_hour > trading_allowed_end_hour ) 
     { 
       Print("should T+1");
       //Calculate the allowed trading time;
     }  
     else if( ( Hour() >= trading_allowed_begin_hour ) && ( Hour() <= trading_allowed_end_hour ))
     {
       Comment("Trading Hour is Allowed!\n");
     }
         
     else
       {  
         DeleteAllLimitOrders();  //cancel all limit orders not yet open after 8:00Am       
         CloseAfterTradingHourOrders();
         //Print("Trading hour is not allowed!");
         //Comment("Trading Hour is not Allowed!Orders are accepted between 00:00-8AM Mountain Time!\n");
         //Comment("All after trading hour orders has been closed!\n");
       }     
      return;

  }

/*
  The function is to check trading history every 10(preset number)trades whether the reward risk ratio is over minimun, 
  if not stop trading 5 days.
*/     
void CheckHistoryRRratio()
  {
    int order_total = OrdersHistoryTotal();
    int open_order_total = 0;
    
    int profit_counter = 0;
    double total_profit = 0;
    
    double order_pl = 0;
    
    int loss_counter = 0;
    double total_loss = 0;
    
    double win_ratio = 0;
    double rr_ratio = 0;
    
    double avg_profit = 0;
    double avg_loss = 0;
    
    for(int i = 0; i < order_total; i++)
    {
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
        if((OrderType() == OP_BUY)||(OrderType() == OP_SELL))
          open_order_total++;
    }
    
    //Print(MinHisTradesToCalRRR);
    //Print(open_order_total);
    
    if( open_order_total >= MinHisTradesToCalRRR)  // if meet the minum history trade to calculate RR ratio
    {
      for(int i = 0; i < order_total; i++)
      {
        if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
        {
          if((OrderType() == OP_BUY)||(OrderType() == OP_SELL))
          {
            order_pl = OrderProfit();
            if( order_pl >=0)
            {
              profit_counter++;
              total_profit+= order_pl;
            }
            else if(order_pl < MinLoss)
            {  
              loss_counter++;
              total_loss+= order_pl;
            }
          }
        }
      }
    }
    
    //Print(loss_counter);
    //Print(profit_counter);
    //Print(total_loss);
    //Print(total_profit);
        
    if(loss_counter == 0) 
    {
      win_ratio = 1;
      rr_ratio = 10;
    }
    else
    {  
      avg_profit = total_profit / profit_counter;
      avg_loss = total_loss / loss_counter;
      win_ratio = profit_counter/loss_counter;
      rr_ratio = MathAbs(avg_profit/avg_loss);
    }
    
    //Print(avg_profit);
    //Print(avg_loss);
    //Print(rr_ratio);    
    
    return;
  }

/*
  The function is to modify order's stoploss
  rule: only reduce stoploss    
*/  

void   ModifySL(int ticket,double sl)
{
        
    if ( OrderSelect(ticket,SELECT_BY_TICKET) )
    {
     int    order_type = OrderType();
     double digits = NormalizeDouble( MarketInfo( OrderSymbol(), MODE_DIGITS ),0 );
     //Print("Digits: ",digits);
     double new_sl = NormalizeDouble(sl,digits);
     double old_sl = OrderStopLoss();
      
      if( (order_type == OP_BUY) || (order_type == OP_BUYLIMIT) || (order_type == OP_BUYSTOP) )
      { 
        if( new_sl > old_sl)
        {
            if(OrderModify(ticket,OrderOpenPrice(),new_sl,OrderTakeProfit(),0,Red))
              Print("Stoploss has been modified---->",new_sl);
            else
              Print("Error in OrderModify. Error code=",GetLastError());   
        }
        
        else if(new_sl == old_sl)
               Print("StopLoss is same!");
             else  
               Print("Against Risk Managment Rule: increase Stoploss can not modify Stoploss!");
      }
      
      else
      {
        if( new_sl < old_sl)
        {
            if(OrderModify(ticket,OrderOpenPrice(),new_sl,OrderTakeProfit(),0,Red))
              Print("Stoploss has been modified---->",new_sl);
            else
              Print("Error in OrderModify. Error code=",GetLastError());   
        }
        
        else if(new_sl == old_sl)
               Print("StopLoss is same!");
             else  
               Print("Against Risk Managment Rule: increase Stoploss can not modify Stoploss!");  
      }
    }
    else   
      Print("there is no order by this ticket: ", ticket);
   
   return;   
}


/*
  The function is to take profit
  rule: only increase take profit    
*/  

void   ModifyTP(int ticket,double tp)
{
    if ( OrderSelect(ticket,SELECT_BY_TICKET) )
    {
     int    order_type = OrderType();
     double digits = NormalizeDouble( MarketInfo( OrderSymbol(), MODE_DIGITS ),0 );
     double new_tp = NormalizeDouble(tp,digits);
     double old_tp = OrderTakeProfit();
      
      if( (order_type == OP_BUY) || (order_type == OP_BUYLIMIT) || (order_type == OP_BUYSTOP) )
      { 
        if( new_tp > old_tp)
        {
            if(OrderModify(ticket,OrderOpenPrice(),OrderStopLoss(),new_tp,0,Blue))
              Print("Take Profit has been modified---->",new_tp);
            else
              Print("Error in OrderModify. Error code=",GetLastError());   
        }
        
        else if(new_tp == old_tp)
               Print("Take Profit is same!");
             else  
               Print("Against Risk Managment Rule: can not decrease Take Profit!");
      }
      
      else
      {
        if( new_tp < old_tp)
        {
            if(OrderModify(ticket,OrderOpenPrice(),OrderStopLoss(),new_tp,0,Blue))
              Print("Take Profit has been modified---->",new_tp);
            else
              Print("Error in OrderModify. Error code=",GetLastError());   
        }
        
        else if(new_tp == old_tp)
               Print("Take Profit is same!");
             else  
               Print("Against Risk Managment Rule: can not decrease Take Profit!");  
      }
    }
    else   
      Print("there is no order by this ticket: ", ticket);
   
   return;     
}


/*
  The function is to modify order's stoploss or and take profit
  rule: only reduce stoploss and increase take profit    
*/  

void   Modify()
  {
    int ticket = 74212692;
    double new_sl = 1.2822;
    double new_tp = 1.2985;
    int order_type = 0;
    double digits = 0;
    
    ModifySL(ticket,new_sl);
    ModifyTP(ticket,new_tp);
    

  }


//-----------------------------------------------------------------------------------------------
   
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---

   /*
     
     Risk Management Rules:
     
     *. If lost 2 in a row, stop tradin for 5 business days.
     *. Total loss limit per week is 4%
     *. Total loss limit per month is 6%
     *. Total drawdown reaches 10%, stop trading for 5 business days.
     *. Check the history rading to calculate RR ratio,if it is < 1.5, stop trading for 5 business days.
     
     *. Must have stoploss and takeprofit for every trade
     *. Risk per trader < max risk per trade specified(2% for now)
     *. All order must be limit order
     *. Total opening and limit order < risk limit (4%)     
     *. Reward/Risk ratio must > 1.5

     *. Limit order is opened after 00:10AM(mountain time)
     *. If limit order is not opened, the order will be deleted on 8:00AM.
     

     *.Stop loss can not be expanded and take profits can only be expanded.
     
   */
   //Rule 5
   //CheckTwoLossInARow();
   
   //Rule 6
   //CheckLossPerWeek();
   
   //Rule 7
   //CheckLossPerMonth();
   
   //Rule8
   //CheckEmergencyStop(); 
   
   //Rule
   //CheckHistoryRRratio();
   
   Modify();
   
   
   //Rule 1
   CheckStopLossTakeProfit();
   
   //Rule 2
   //CheckRiskperTrade();
   
   //Rule 12
   //CheckRRRatio();   
   
   //Rule 3
   //CheckIsLimitOrder();
   
   //Rule 4
   //CheckTotalTradeRisk();
   
   //Rule 5 to make sure the limit order is opened between 00:00AM and 8:0AM. if not delete all the limit orders
   //CheckOrderOpenTime();
   
   
   
     
  }
//+------------------------------------------------------------------+
