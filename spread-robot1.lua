--[[
1. Мониторим один инструмент, по нему же открываем позицию. Красс и код инструмента задается константами SEC и CLASS.
2. В константе MIN_P_SPREAD задается пороговый процент спреда (в процентах). Например 0,1.
3. Следим за лучшими аск и бид по указанной бумаге.
4. Если спред расширяется до MIN_P_SPREAD или более и время сессии торговое, то становимся лучшим бидом в размере 1 лот. Если спред сужается ниже порогового - уходим.
5. Если второй под нами человек в стакане опускается, и нам есть куда опуститься, мы тоже опускаемся, оставаясь лучшими.
6. Если нас акцептовали, образовалась длинная позиция по нашему инструменту, то мы его тут же выставляем на продажу (1 лот), встав лучшими на офере. Если нас обгоняют на офере, мы тоже обгоняем. Если второй офер над нами подымается, мы тоже поднимаемся. Т.е. поддерживаем цену заявки такой, чтобы она была лучшей в стакане.
7. Продав имеющуюся бумагу, начинаем алгоритм по новой.

Версия: 0.99
]]

-- Константы --

MIN_P_SPREAD = 1    -- минимальный пороговый процент спреда
MIN_SPREAD_STEP = 7     -- минимальное количество шагов спреда, когда открываем позицию
SEC = "RI95000BF5"
CLASS = "SPBOPT"

security_info = getSecurityInfo(CLASS, SEC)

PRICE_STEP = 10  -- шаг цены по инструменту
PRICE_SCALE = 1   -- точность задания цены инструмента

TRADE_ACC   = "SPBFUT012LV"   -- торговый счет
CLIENT_CODE = "000000271327"          -- код клиента

--[[
Переменная состояния:
'0'  - нашей котировки нет, ждем нужного спреда, при его возникновении выставляем заявку на покупку
‘OB’ – выставлена заявка на покупку, ждем ответа на транзакцию
'N'  - активна заявка на покупку, позиция не открыта, удерживаем позицию лучшего спроса в стакане
'1'  - открылась длинная позиция, необходимо выставитьзаявку на продажу
‘OS’ – выставлена заявка на продажу, ждем ответа на транзакцию
'L'  - открылась длинная позиция, удерживаем позицию лучшего предложения
'MB' - снята активная заявка, необходимо перевыставить новую на покупку
'MS' - снята активная заявка, необходимо перевыставить новую на продажу
]]
CURRENT_STATE = '0'

-- Глобальные переменные --

current_order_num = 0    -- номер текущей активной заявки
current_order_price = 0  -- цена в текущей активной заявке
uniq_trans_id = 0        -- уникальный номер последней отправленной транзакции



------------------------
is_run = true

function OnStop(s)
  l_file:close()
  is_run = false
end

function main()
  while is_run do
    sleep(50)
  end
end

------------------------

-- Сформировать цену в строковом представлении с учетом PRICE_SCALE
function MakeStringPrice(price)

  local n,m = math.modf(price)
  n = tostring(n)
  if PRICE_SCALE > 0 then
    m = math.floor(m * 10^PRICE_SCALE + 0.01)
    if m > 0.1 then
      m = string.sub(tostring(m), 1, PRICE_SCALE)
      m = string.rep('0', PRICE_SCALE - string.len(m)) .. m
    else
      m = string.rep('0', PRICE_SCALE)
    end
    m = '.' .. m
  else
    m = ''
  end
  
  return (n .. m)

end


-- Снимает активную заявку
function KillOrder()

  if (CURRENT_STATE ~= 'N') and (CURRENT_STATE ~= 'L') then  -- снятие заявки должно вызываться только в тех состояниях, когда заявка выставлена и активна
    return
  end

  uniq_trans_id = uniq_trans_id + 1

  local trans = {
          ["ACTION"] = "KILL_ORDER",
          ["CLASSCODE"] = CLASS,
          ["SECCODE"] = SEC,
          ["ORDER_KEY"] = tostring(current_order_num),
          ["TRANS_ID"] = tostring(uniq_trans_id)
                }

  local res = sendTransaction(trans)
  l_file:write(os.date().." Kill : " .. res.."\n")

  -- изменим состояние на "ожидаем ответа на транзакцию снятия заявки"
  if CURRENT_STATE == 'N' then
    CURRENT_STATE = 'MB'     -- N --> MB
  else
    CURRENT_STATE = 'MS'     -- L --> MS
  end

end


-- Выставляет заявку по указанной цене и заданного напрпавления
function SendOrder(buy_sell, price)

  uniq_trans_id = uniq_trans_id + 1

  local trans = {
          ["ACTION"] = "NEW_ORDER",
          ["CLASSCODE"] = CLASS,
          ["SECCODE"] = SEC,
          ["ACCOUNT"] = TRADE_ACC,
          ["OPERATION"] = buy_sell,
          ["PRICE"] = tostring(price), --MakeStringPrice(price),
          ["QUANTITY"] = tostring(1),
          ["TRANS_ID"] = tostring(uniq_trans_id)
                }

  local res = sendTransaction(trans)
  l_file:write(os.date().." Send : " .. res.."\n")
  current_order_price = price

end


-- Проверяет условия выставления котировки покупку
-- Если условия соблюдаются - выставляет заявку на покупку на позицию лучше самого лучшего спроса
function MakeOrderBuy()

  if (CURRENT_STATE ~= '0') then  -- выставление заявки должно вызываться только при отсутствии активной
    return
  end

  local qt = getQuoteLevel2(CLASS, SEC)
  if qt == nil then         --не работает!!!
    return                     -- защита от некорректно заданного инструмента
  end
  l_file:write(os.date().." "..tostring(qt.bid_count+0) .. " -- " .. tostring(qt.offer_count+0).."\n")
  if ((qt.bid_count+0 == 0) or (qt.offer_count+0 == 0)) then
    return                     -- стакан пуст, заявку не ставим
  end
    
  local bid = qt.bid[qt.bid_count+0].price
  local offer = qt.offer[1].price
  local p_spread = (offer - bid) / bid * 100
  local spread_step = math.floor((offer - bid) / PRICE_STEP + 0.01)

  l_file:write(os.date().." bid=" .. tostring(bid) .. " offer=" .. tostring(offer) .. " %=" .. tostring(p_spread) .. " s_step=" .. tostring(spread_step) .. " CURRENT_STATE=" .. CURRENT_STATE.."\n")
  
  if (p_spread >= MIN_P_SPREAD) and (spread_step >= MIN_SPREAD_STEP) then
    l_file:write(os.date().." TRY TO OPEN POSITION\n")
    SendOrder('B', bid + PRICE_STEP)
    CURRENT_STATE = 'OB'     -- выставить состояние "ждем ответа на транзакцию заявки покупки"
  end

end


-- Выставляет заявку на продажу на позицию лучше самого лучшего предложения
function MakeOrderSell()

  if (CURRENT_STATE ~= '1') then  -- выставление заявки должно вызываться только при отсутствии активной
    return
  end

  local qt = getQuoteLevel2(CLASS, SEC)
  if ((qt.bid_count+0 == 0) or (qt.offer_count+0 == 0)) then
    return                     -- стакан пуст, заявку не ставим
  end
    
  local offer = qt.offer[1].price
  l_file:write(os.date().." MakeOrderSell offer=" .. tostring(offer).."\n")
  SendOrder('S', offer - PRICE_STEP)
  CURRENT_STATE = 'OS'     -- выставить состояние "ждем ответа на транзакцию заявки продажи"

end


-- Проверяет находится ли наша заявка в лучшей позиции спроса
-- Цена нашей заявки сохранена в current_order_price
function CheckBidPosition()

  if (CURRENT_STATE ~= 'N') then  -- должно вызываться только при активной заявке
    return
  end

  local qt = getQuoteLevel2(CLASS, SEC)
  if ((qt.bid_count+0 == 0) or (qt.offer_count+0 == 0)) then
    return                     -- стакан пуст, проверять нечего
  end
    
  local bid = tonumber(qt.bid[qt.bid_count+0].price)   -- котировка лучшего предложения
  
  -- проверим: наша котировка на лучшей позиции?
  -- если нет - снимем заявку для перевыставления в лучшую позицию и сразу выйдем
  if (bid - current_order_price) > (PRICE_STEP / 2) then
    KillOrder()
	return
  end
  
  -- проверим: отстоит ли наша котировка только на 1 шаг от предыдущих?
  -- если отстоит дальше одного шага - снимем заявку для перевыставления в лучшую позицию в одном шаге
  if (qt.bid_count+0 > 1) then  -- проверяем только если в стакане боолее одной котировки
    local prev_bid = tonumber(qt.bid[qt.bid_count-1].price)
    if (current_order_price - prev_bid) > (PRICE_STEP * 1.5) then
      KillOrder()
      return
	 end
  end

end


-- Проверяет находится ли наша заявка в лучшей позиции предложения
-- Цена нашей заявки сохранена в current_order_price
function CheckOfferPosition()

  if (CURRENT_STATE ~= 'L') then  -- должно вызываться только при активной заявке
    return
  end

  local qt = getQuoteLevel2(CLASS, SEC)
  if ((qt.bid_count+0 == 0) or (qt.offer_count+0 == 0)) then
    return                     -- стакан пуст, проверять нечего
  end
    
  local offer = tonumber(qt.offer[1].price)   -- котировка лучшего спроса
  
  -- проверим: наша котировка на лучшей позиции?
  -- если нет - снимем заявку для перевыставления в лучшую позицию и сразу выйдем
  if (current_order_price - offer) > (PRICE_STEP / 2) then
    KillOrder()
	return
  end
  
  -- проверим: отстоит ли наша котировка только на 1 шаг от предыдущих?
  -- если отстоит дальше одного шага - снимем заявку для перевыставления в лучшую позицию в одном шаге
  if (qt.offer_count+0 > 1) then  -- проверяем только если в стакане боолее одной котировки
    local prev_offer = tonumber(qt.offer[2].price)
    if (prev_offer - current_order_price) > (PRICE_STEP * 1.5) then
      KillOrder()
      return
	 end
  end

end


---- обработчики событий ----

function OnInit(s)
--  SendOrder('B', 2000.1)
  l_file=io.open("C:\\log\\spreadbot_" ..getTradeDate().date.."_"..os.time()..".log", "w")
  l_file:write("Информация по торгуемуму инструменту:".."\n")
  l_file:write("Код инструмента: "..security_info.sec_code.."\n")
  l_file:write("Наименование инструмента: "..security_info.name.."\n")
  l_file:write("Краткое наименование: "..security_info.short_name.."\n")
  l_file:write("Код класса: "..security_info.class_code.."\n")
  l_file:write("Наименование класса: "..security_info.class_name.."\n")
  l_file:write("Номинал: "..security_info.face_value.."\n")
  l_file:write("Код валюты номинала: "..security_info.face_unit.."\n")
  l_file:write("Количество значащих цифр после запятой: "..tostring(security_info.scale).."\n")
  MakeOrderBuy()
end


function OnQuote(class_code, sec_code)

  -- отслеживаем котировки только по нашему инструменту
  if (class_code ~= CLASS) or (sec_code ~= SEC) then
    return
  end

  l_file:write(os.date().." OnQuote: CURRENT_STATE=" .. CURRENT_STATE.."\n")

  -- какие-либо действия выполняются только в определенных состояниях
  if (CURRENT_STATE ~= '0') and (CURRENT_STATE ~= 'N') and (CURRENT_STATE ~= 'L') then
    return
  end

  if     (CURRENT_STATE == '0') then  -- если позиция не открыта и нет заявки
    MakeOrderBuy()            -- открыть позицию в случае подходящих условий
  elseif (CURRENT_STATE == 'N') then  -- если позиция не открыта и активна заявка на покупку
    CheckBidPosition()            -- проверить находится ли наша заявка в лучшей позиции спроса
  elseif (CURRENT_STATE == 'L') then  -- если позиция не открыта и активна заявка на покупку
    CheckOfferPosition()          -- проверить находится ли наша заявка в лучшей позиции предложения
  end

end


function OnTransReply(repl)
  
  l_file:write(os.date().." TrRepl = " .. tostring(repl.status) .. " o_num=" .. tostring(repl.ordernum) .. " R=" .. tostring(repl.R) .. " [" .. repl.result_msg .. "]" .. " uid=" .. tostring(repl.uid) .. " price=" .. tostring(repl.price) .. " quantity=" .. tostring(repl.quantity) ..  " cl_code=" .. tostring(repl.client_code) .. " CURRENT_STATE=" .. CURRENT_STATE.."\n")

  if (uniq_trans_id ~= repl.R) then
    l_file:write(os.date().." TrRepl NO LAST TRAN\n")
    return
  end


  if     (CURRENT_STATE == 'OB') then  -- если ждем результата выставления заявки на покупку
    current_order_num = repl.ordernum
	if current_order_num ~= 0 then  -- заявка выставлена успешно?
	  CURRENT_STATE = 'N'
	 else
	  CURRENT_STATE = '0'
	 end
  elseif (CURRENT_STATE == 'MB') then  -- если ждем результата снятия заявки на покупку
    if (repl.status == 3) then  -- только если снятие было успешным, иначе скорее всего была сделка - ничего не делаем
      CURRENT_STATE = '0'  -- состояние "заявки нет, позиции нет"
      MakeOrderBuy()        -- и тут же ее перевыставляем
    end
  elseif (CURRENT_STATE == 'OS') then  -- если ждем результата выставления заявки на продажу
    current_order_num = repl.ordernum
	if current_order_num ~= 0 then  -- заявка выставлена успешно?
	  CURRENT_STATE = 'L'
	 else
	  CURRENT_STATE = '1'
	 end
  elseif (CURRENT_STATE == 'MS') then  -- если ждем результата снятия заявки на продажу
    if (repl.status == 3) then  -- только если снятие было успешным, иначе скорее всего была сделка - ничего не делаем
      CURRENT_STATE = '1'  -- состояние "заявки нет, позиция есть"
      MakeOrderSell()       -- и тут же ее перевыставляем
    end
  end

end


function OnTrade(trade)

  l_file:write(os.date().." OnTrade: CURRENT_STATE=" .. CURRENT_STATE.."\n")

  if     (CURRENT_STATE == 'N') or (CURRENT_STATE == 'OB') or (CURRENT_STATE == 'MB') then    -- если была активна заявка на покупку, значит открылась длинная позиция
    CURRENT_STATE = '1'
    MakeOrderSell()                     -- выставим заявку на продажу
  elseif (CURRENT_STATE == 'L') or (CURRENT_STATE == 'OS') or (CURRENT_STATE == 'MS') then    -- если была активна заявка на продажу, значит закрылась длинная позиция
    CURRENT_STATE = '0'
    MakeOrderBuy()                      -- снова выставим заявку на покупку
  end

end
