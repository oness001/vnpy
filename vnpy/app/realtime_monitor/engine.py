#!/usr/bin/python
# -*- coding:utf-8 -*-

"""
@author:Hadrianl

"""

from vnpy.event import EventEngine, Event
from vnpy.trader.engine import BaseEngine, MainEngine
from vnpy.trader.event import (
    EVENT_TICK, EVENT_ORDER, EVENT_TRADE, EVENT_LOG)
from vnpy.trader.constant import (Direction, Offset, OrderType,Interval)
from vnpy.trader.object import (SubscribeRequest, OrderRequest, LogData)
from vnpy.trader.utility import load_json, save_json
from vnpy.trader.ibdata import ibdata_client
from vnpy.trader.object import BarData
import weakref
import datetime as dt
from dateutil import parser
from threading import Thread
from queue import Empty
# from .template import AlgoTemplate


APP_NAME = "MarketDataVisulization"

EVENT_MKDATA_LOG = "eMKDataLog"
EVENT_ALGO_SETTING = "eAlgoSetting"
EVENT_ALGO_VARIABLES = "eAlgoVariables"
EVENT_ALGO_PARAMETERS = "eAlgoParameters"
EVENT_BAR_UPDATE = 'eBarUpdate'


class MarketDataEngine(BaseEngine):
    """"""
    setting_filename = "market_data_visulization_setting.json"

    def __init__(self, main_engine: MainEngine, event_engine: EventEngine):
        """Constructor"""
        super().__init__(main_engine, event_engine, APP_NAME)

        self.symbol_mkdata_map = {}
        self.symbol_order_map = {}
        self.symbol_trade_map = {}
        self.realtimebar_threads = {}
        self.first = True

        self.register_event()
        self.init_engine()

    def init_engine(self):
        """"""
        self.write_log("市场数据可视化引擎启动")
        self.init_ibdata()

    def init_ibdata(self):
        """
        Init RQData client.
        """
        result = ibdata_client.init()
        if result:
            self.write_log("IBData数据接口初始化成功")

    def register_event(self):
        """"""
        self.event_engine.register(EVENT_TICK, self.process_tick_event)
        self.event_engine.register(EVENT_ORDER, self.process_order_event)
        self.event_engine.register(EVENT_TRADE, self.process_trade_event)
        self.event_engine.register(EVENT_BAR_UPDATE, self.process_bar_event)

    def process_tick_event(self, event: Event):
        """"""
        tick = event.data
        # print(tick)
        if self.first:
            self.subscribe('359142357.HKFE', Interval.MINUTE)
            self.first = False

        #TODO: update tick


    def process_trade_event(self, event: Event):
        """"""
        trade = event.data

        #TODO: mark the trade

    def process_order_event(self, event: Event):
        """"""
        order = event.data

        #TODO:mark the order

    def process_bar_event(self, event: Event):
        bar = event.data
        print(bar)
        # TODO:updatebar the order

    def subscribe(self,req: SubscribeRequest, interval: Interval, barCount=300):
        """"""
        contract = self.main_engine.get_contract(req.vt_symbol)
        if not contract:
            self.write_log(f'订阅行情失败，找不到合约：{vt_symbol}')
            return

        ibdata_client.subscribe_bar(req, interval, barCount)
        self.realtimebar_threads[(req.vt_symbol, interval)] = Thread(target=self.handle_bar_update, args=(req, interval))
        self.realtimebar_threads[(req.vt_symbol, interval)].start()

    def unsubscribe(self, req: SubscribeRequest, interval: Interval):
        ibdata_client.unsubscribe_bar(req, interval)

    def handle_bar_update(self, req: SubscribeRequest, interval: Interval): #FIXME:not an efficient way
        reqId = ibdata_client.subscription2reqId((req.vt_symbol, interval))
        q = ibdata_client.result_queues[reqId]
        # event_type = EVENT_BAR_UPDATE + req.vt_symbol + '.' + interval.value
        event_type = EVENT_BAR_UPDATE
        # self.event_engine.register(event_type)
        while ibdata_client.isConnected():
            try:
                ib_bar = q.get(timeout=60)
            except Empty:
                continue

            if isinstance(ib_bar, int):
                break

            vt_bar = BarData(symbol=req.symbol,
                             exchange=req.exchange,
                             datetime=parser.parse(ib_bar.date),
                             interval=interval,
                             volume=ib_bar.volume,
                             open_price=ib_bar.open,
                             high_price=ib_bar.high,
                             low_price=ib_bar.low,
                             close_price=ib_bar.close,
                             gateway_name='IB')
            event = Event(event_type, vt_bar)
            self.event_engine.put(event)

    def get_tick(self, vt_symbol: str):
        """"""
        tick = self.main_engine.get_tick(vt_symbol)

        if not tick:
            self.write_log(f"查询行情失败，找不到行情：{vt_symbol}")

        return tick

    def get_contract(self, vt_symbol: str):
        """"""
        contract = self.main_engine.get_contract(vt_symbol)

        if not contract:
            self.write_log(f"查询合约失败，找不到合约：{vt_symbol}")

        return contract

    def write_log(self, msg: str):
        """"""

        event = Event(EVENT_LOG)
        log = LogData(msg=msg, gateway_name='IB')
        event.data = log
        self.event_engine.put(event)
