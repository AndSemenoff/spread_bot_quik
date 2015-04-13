--[[
1. ��������� ���� ����������, �� ���� �� ��������� �������. ����� � ��� ����������� �������� ����������� SEC � CLASS.
2. � ��������� MIN_P_SPREAD �������� ��������� ������� ������ (� ���������). �������� 0,1.
3. ������ �� ������� ��� � ��� �� ��������� ������.
4. ���� ����� ����������� �� MIN_P_SPREAD ��� ����� � ����� ������ ��������, �� ���������� ������ ����� � ������� 1 ���. ���� ����� �������� ���� ���������� - ������.
5. ���� ������ ��� ���� ������� � ������� ����������, � ��� ���� ���� ����������, �� ���� ����������, ��������� �������.
6. ���� ��� �����������, ������������ ������� ������� �� ������ �����������, �� �� ��� ��� �� ���������� �� ������� (1 ���), ����� ������� �� �����. ���� ��� �������� �� �����, �� ���� ��������. ���� ������ ���� ��� ���� ����������, �� ���� �����������. �.�. ������������ ���� ������ �����, ����� ��� ���� ������ � �������.
7. ������ ��������� ������, �������� �������� �� �����.

������: 0.99
]]

-- ��������� --

MIN_P_SPREAD = 1    -- ����������� ��������� ������� ������
MIN_SPREAD_STEP = 7     -- ����������� ���������� ����� ������, ����� ��������� �������
SEC = "RI95000BF5"
CLASS = "SPBOPT"

security_info = getSecurityInfo(CLASS, SEC)

PRICE_STEP = 10  -- ��� ���� �� �����������
PRICE_SCALE = 1   -- �������� ������� ���� �����������

TRADE_ACC   = "SPBFUT012LV"   -- �������� ����
CLIENT_CODE = "000000271327"          -- ��� �������

--[[
���������� ���������:
'0'  - ����� ��������� ���, ���� ������� ������, ��� ��� ������������� ���������� ������ �� �������
�OB� � ���������� ������ �� �������, ���� ������ �� ����������
'N'  - ������� ������ �� �������, ������� �� �������, ���������� ������� ������� ������ � �������
'1'  - ��������� ������� �������, ���������� ��������������� �� �������
�OS� � ���������� ������ �� �������, ���� ������ �� ����������
'L'  - ��������� ������� �������, ���������� ������� ������� �����������
'MB' - ����� �������� ������, ���������� ������������� ����� �� �������
'MS' - ����� �������� ������, ���������� ������������� ����� �� �������
]]
CURRENT_STATE = '0'

-- ���������� ���������� --

current_order_num = 0    -- ����� ������� �������� ������
current_order_price = 0  -- ���� � ������� �������� ������
uniq_trans_id = 0        -- ���������� ����� ��������� ������������ ����������



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

-- ������������ ���� � ��������� ������������� � ������ PRICE_SCALE
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


-- ������� �������� ������
function KillOrder()

  if (CURRENT_STATE ~= 'N') and (CURRENT_STATE ~= 'L') then  -- ������ ������ ������ ���������� ������ � ��� ����������, ����� ������ ���������� � �������
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

  -- ������� ��������� �� "������� ������ �� ���������� ������ ������"
  if CURRENT_STATE == 'N' then
    CURRENT_STATE = 'MB'     -- N --> MB
  else
    CURRENT_STATE = 'MS'     -- L --> MS
  end

end


-- ���������� ������ �� ��������� ���� � ��������� ������������
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


-- ��������� ������� ����������� ��������� �������
-- ���� ������� ����������� - ���������� ������ �� ������� �� ������� ����� ������ ������� ������
function MakeOrderBuy()

  if (CURRENT_STATE ~= '0') then  -- ����������� ������ ������ ���������� ������ ��� ���������� ��������
    return
  end

  local qt = getQuoteLevel2(CLASS, SEC)
  if qt == nil then         --�� ��������!!!
    return                     -- ������ �� ����������� ��������� �����������
  end
  l_file:write(os.date().." "..tostring(qt.bid_count+0) .. " -- " .. tostring(qt.offer_count+0).."\n")
  if ((qt.bid_count+0 == 0) or (qt.offer_count+0 == 0)) then
    return                     -- ������ ����, ������ �� ������
  end
    
  local bid = qt.bid[qt.bid_count+0].price
  local offer = qt.offer[1].price
  local p_spread = (offer - bid) / bid * 100
  local spread_step = math.floor((offer - bid) / PRICE_STEP + 0.01)

  l_file:write(os.date().." bid=" .. tostring(bid) .. " offer=" .. tostring(offer) .. " %=" .. tostring(p_spread) .. " s_step=" .. tostring(spread_step) .. " CURRENT_STATE=" .. CURRENT_STATE.."\n")
  
  if (p_spread >= MIN_P_SPREAD) and (spread_step >= MIN_SPREAD_STEP) then
    l_file:write(os.date().." TRY TO OPEN POSITION\n")
    SendOrder('B', bid + PRICE_STEP)
    CURRENT_STATE = 'OB'     -- ��������� ��������� "���� ������ �� ���������� ������ �������"
  end

end


-- ���������� ������ �� ������� �� ������� ����� ������ ������� �����������
function MakeOrderSell()

  if (CURRENT_STATE ~= '1') then  -- ����������� ������ ������ ���������� ������ ��� ���������� ��������
    return
  end

  local qt = getQuoteLevel2(CLASS, SEC)
  if ((qt.bid_count+0 == 0) or (qt.offer_count+0 == 0)) then
    return                     -- ������ ����, ������ �� ������
  end
    
  local offer = qt.offer[1].price
  l_file:write(os.date().." MakeOrderSell offer=" .. tostring(offer).."\n")
  SendOrder('S', offer - PRICE_STEP)
  CURRENT_STATE = 'OS'     -- ��������� ��������� "���� ������ �� ���������� ������ �������"

end


-- ��������� ��������� �� ���� ������ � ������ ������� ������
-- ���� ����� ������ ��������� � current_order_price
function CheckBidPosition()

  if (CURRENT_STATE ~= 'N') then  -- ������ ���������� ������ ��� �������� ������
    return
  end

  local qt = getQuoteLevel2(CLASS, SEC)
  if ((qt.bid_count+0 == 0) or (qt.offer_count+0 == 0)) then
    return                     -- ������ ����, ��������� ������
  end
    
  local bid = tonumber(qt.bid[qt.bid_count+0].price)   -- ��������� ������� �����������
  
  -- ��������: ���� ��������� �� ������ �������?
  -- ���� ��� - ������ ������ ��� ��������������� � ������ ������� � ����� ������
  if (bid - current_order_price) > (PRICE_STEP / 2) then
    KillOrder()
	return
  end
  
  -- ��������: ������� �� ���� ��������� ������ �� 1 ��� �� ����������?
  -- ���� ������� ������ ������ ���� - ������ ������ ��� ��������������� � ������ ������� � ����� ����
  if (qt.bid_count+0 > 1) then  -- ��������� ������ ���� � ������� ������ ����� ���������
    local prev_bid = tonumber(qt.bid[qt.bid_count-1].price)
    if (current_order_price - prev_bid) > (PRICE_STEP * 1.5) then
      KillOrder()
      return
	 end
  end

end


-- ��������� ��������� �� ���� ������ � ������ ������� �����������
-- ���� ����� ������ ��������� � current_order_price
function CheckOfferPosition()

  if (CURRENT_STATE ~= 'L') then  -- ������ ���������� ������ ��� �������� ������
    return
  end

  local qt = getQuoteLevel2(CLASS, SEC)
  if ((qt.bid_count+0 == 0) or (qt.offer_count+0 == 0)) then
    return                     -- ������ ����, ��������� ������
  end
    
  local offer = tonumber(qt.offer[1].price)   -- ��������� ������� ������
  
  -- ��������: ���� ��������� �� ������ �������?
  -- ���� ��� - ������ ������ ��� ��������������� � ������ ������� � ����� ������
  if (current_order_price - offer) > (PRICE_STEP / 2) then
    KillOrder()
	return
  end
  
  -- ��������: ������� �� ���� ��������� ������ �� 1 ��� �� ����������?
  -- ���� ������� ������ ������ ���� - ������ ������ ��� ��������������� � ������ ������� � ����� ����
  if (qt.offer_count+0 > 1) then  -- ��������� ������ ���� � ������� ������ ����� ���������
    local prev_offer = tonumber(qt.offer[2].price)
    if (prev_offer - current_order_price) > (PRICE_STEP * 1.5) then
      KillOrder()
      return
	 end
  end

end


---- ����������� ������� ----

function OnInit(s)
--  SendOrder('B', 2000.1)
  l_file=io.open("C:\\log\\spreadbot_" ..getTradeDate().date.."_"..os.time()..".log", "w")
  l_file:write("���������� �� ���������� �����������:".."\n")
  l_file:write("��� �����������: "..security_info.sec_code.."\n")
  l_file:write("������������ �����������: "..security_info.name.."\n")
  l_file:write("������� ������������: "..security_info.short_name.."\n")
  l_file:write("��� ������: "..security_info.class_code.."\n")
  l_file:write("������������ ������: "..security_info.class_name.."\n")
  l_file:write("�������: "..security_info.face_value.."\n")
  l_file:write("��� ������ ��������: "..security_info.face_unit.."\n")
  l_file:write("���������� �������� ���� ����� �������: "..tostring(security_info.scale).."\n")
  MakeOrderBuy()
end


function OnQuote(class_code, sec_code)

  -- ����������� ��������� ������ �� ������ �����������
  if (class_code ~= CLASS) or (sec_code ~= SEC) then
    return
  end

  l_file:write(os.date().." OnQuote: CURRENT_STATE=" .. CURRENT_STATE.."\n")

  -- �����-���� �������� ����������� ������ � ������������ ����������
  if (CURRENT_STATE ~= '0') and (CURRENT_STATE ~= 'N') and (CURRENT_STATE ~= 'L') then
    return
  end

  if     (CURRENT_STATE == '0') then  -- ���� ������� �� ������� � ��� ������
    MakeOrderBuy()            -- ������� ������� � ������ ���������� �������
  elseif (CURRENT_STATE == 'N') then  -- ���� ������� �� ������� � ������� ������ �� �������
    CheckBidPosition()            -- ��������� ��������� �� ���� ������ � ������ ������� ������
  elseif (CURRENT_STATE == 'L') then  -- ���� ������� �� ������� � ������� ������ �� �������
    CheckOfferPosition()          -- ��������� ��������� �� ���� ������ � ������ ������� �����������
  end

end


function OnTransReply(repl)
  
  l_file:write(os.date().." TrRepl = " .. tostring(repl.status) .. " o_num=" .. tostring(repl.ordernum) .. " R=" .. tostring(repl.R) .. " [" .. repl.result_msg .. "]" .. " uid=" .. tostring(repl.uid) .. " price=" .. tostring(repl.price) .. " quantity=" .. tostring(repl.quantity) ..  " cl_code=" .. tostring(repl.client_code) .. " CURRENT_STATE=" .. CURRENT_STATE.."\n")

  if (uniq_trans_id ~= repl.R) then
    l_file:write(os.date().." TrRepl NO LAST TRAN\n")
    return
  end


  if     (CURRENT_STATE == 'OB') then  -- ���� ���� ���������� ����������� ������ �� �������
    current_order_num = repl.ordernum
	if current_order_num ~= 0 then  -- ������ ���������� �������?
	  CURRENT_STATE = 'N'
	 else
	  CURRENT_STATE = '0'
	 end
  elseif (CURRENT_STATE == 'MB') then  -- ���� ���� ���������� ������ ������ �� �������
    if (repl.status == 3) then  -- ������ ���� ������ ���� ��������, ����� ������ ����� ���� ������ - ������ �� ������
      CURRENT_STATE = '0'  -- ��������� "������ ���, ������� ���"
      MakeOrderBuy()        -- � ��� �� �� ��������������
    end
  elseif (CURRENT_STATE == 'OS') then  -- ���� ���� ���������� ����������� ������ �� �������
    current_order_num = repl.ordernum
	if current_order_num ~= 0 then  -- ������ ���������� �������?
	  CURRENT_STATE = 'L'
	 else
	  CURRENT_STATE = '1'
	 end
  elseif (CURRENT_STATE == 'MS') then  -- ���� ���� ���������� ������ ������ �� �������
    if (repl.status == 3) then  -- ������ ���� ������ ���� ��������, ����� ������ ����� ���� ������ - ������ �� ������
      CURRENT_STATE = '1'  -- ��������� "������ ���, ������� ����"
      MakeOrderSell()       -- � ��� �� �� ��������������
    end
  end

end


function OnTrade(trade)

  l_file:write(os.date().." OnTrade: CURRENT_STATE=" .. CURRENT_STATE.."\n")

  if     (CURRENT_STATE == 'N') or (CURRENT_STATE == 'OB') or (CURRENT_STATE == 'MB') then    -- ���� ���� ������� ������ �� �������, ������ ��������� ������� �������
    CURRENT_STATE = '1'
    MakeOrderSell()                     -- �������� ������ �� �������
  elseif (CURRENT_STATE == 'L') or (CURRENT_STATE == 'OS') or (CURRENT_STATE == 'MS') then    -- ���� ���� ������� ������ �� �������, ������ ��������� ������� �������
    CURRENT_STATE = '0'
    MakeOrderBuy()                      -- ����� �������� ������ �� �������
  end

end
