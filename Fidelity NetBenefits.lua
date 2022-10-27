WebBanking{
  version     = 0.10,
  url         = "https://nb.fidelity.com/public/nb/worldwide/home?AuthRedUrl=https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PlanSummary",
  services    = {"Fidelity NetBenefits"},
  description = "Get securities and their current value from the Fidelity NetBenefits website"
}

CONSTANTS = {
  homepage = "https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PlanSummary",
  login = "https://login.fidelity.com/ftgw/Fas/Fidelity/PWI/Login/Response/dj.chf.ra/",
  logout = "https://netbenefitsww.fidelity.com/Catalina/LongBeach?Command=LOGOUT&Realm=mybenefitsww",
  overview = "https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PositionSummary?ACCOUNT=",
  position = "https://netbenefitsww.fidelity.com/mybenefitsww/spsaccounts/api/position?ACCOUNT="
}

g_cookies = ""

function SupportsBank (protocol, bankCode)
  local bankSupported = (protocol == ProtocolWebBanking) and (bankCode == services[1])
  return bankSupported
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
  local connection = Connection()
  local html = HTML(connection:get(url))

  local url, postContent, postContentType, headers = loginPostRequest(username, password, connection:getCookies())
  content = connection:request("POST", url, postContent, postContentType, headers)

  if (string.find(content, "We are Sorry.  There was a Technical Issue.")) then
    return "Fidelity is having technical issues or is throttling your logins. Please try again later"
  end

  g_cookies = connection:getCookies()
end

function ListAccounts (knownAccounts)
  local connection = Connection()

  local html = HTML(connection:request("GET", CONSTANTS.homepage, nil, nil, {["Cookie"] = g_cookies} ))

  -- Account Details
  local accoutName = html:xpath('//*[@id="tile3"]/h2'):text()

  local stockPlanAccountLink = html:xpath('//*[@id="espp-tables"]/div[contains(@class, \'full-transaction-history\')]//a'):attr("href")
  local number = stockPlanAccountLink:match("?ACCOUNT=(%w+)_.*")

  if (number == nil or number == '') then
    return "We could not find any Fidelity accounts. Make sure you have active positions in your account."
  end

  local subAccount = html:xpath('//*[@id="tile3"]/div[2]'):text():match(".*(%a%d+)$")

  local account = {
    name = titlecase(accoutName),
    accountNumber = number,
    subAccount = subAccount,
    portfolio = true,
    currency = "EUR",
    type = AccountTypePortfolio
  }
  return {account}
end

function RefreshAccount (account, since)
  if (account.accountNumber == nil or account.accountNumber == '') then
    return "Could not refresh account because we could not find a valid account number."
  end

  local headers = {
    ["Cookie"] = g_cookies,
    ["Accept"] = "application/json"
  }
  local connection = Connection()
  local json = JSON(connection:request("GET", CONSTANTS.position .. account.accountNumber, nil, nil, headers )):dictionary()

  return {balance=extractBalance(json), securities=extractSecurities(json)}
end

function EndSession ()
  local connection = Connection()
  local html = HTML(connection:request("GET", CONSTANTS.logout, nil, nil, {["Cookie"] = g_cookies}))
  g_cookies = ""
end


function loginPostRequest (username, password, cookies)
  local url = CONSTANTS.login
  local content = "username=" .. username .. "&password=" .. password .. "&SavedIdInd=N"
  local contentType = "application/x-www-form-urlencoded; charset=UTF-8"

  -- Extracting the _abck
  --local abckCookie = cookies:match('(_abck=.*);?')
  --local generatedCookie = "JSESSIONID=" .. randomJsessionId() .. "; " .. abckCookie .. "; "

  local abckCookie = "_abck=B0C2C284ED0000FBD02EC595F6E7BEDE~0~YAAQbplkX7sqg+19AQAA/mss8gfv0+1yssAIYX4JeFH09Cm/z4nwujGbqNFquNW5PeFKzcOspQqK6GqjT17SSS/N3Gul3L5E3sl20Jexeh6nEhUzoD2nmCwCceHCBRaE+TfZ9N53lCQh3f5GBzn2g5wKVjQWb8JIke0MFKtmbv5S9WrSQcMLBBQSvNcz3tdIDYxoNMT5aKEHYHQZI6zKJQajihZzKIW1Fw4R5Bs/pqoIYXWRZgMQu1AqfQSaEZwVwvn6M55buPglQu5CTGFCJgSE9qgoSNO365SgIFWnkGmBzJOEXm/XoxZBQt0bjUjLn91nmtCikgOY5AQS7Xj5tFol9o4yiEMCSljpVE/FYKBIT7lupiCN65WXRbPu/UXgLuOLClTF20MGGt884byal4dJvIxY0M8jo+Ya~-1~-1~-1; "
  local cookie = "JSESSIONID=" .. randomJsessionId() .. "; " .. abckCookie
  local headers = {
    Cookie = cookie
  }

  return url, content, contentType, headers
end

function extractBalance (json)
  local balance = json.accountDetails.displayAccountsBalance.totalClosingMktVal.value
  return balance
end

function extractSecurities (json)
  local currency = json.exchangeRate.toCurrency
  local originalCurrency = json.exchangeRatefromCurrency
  local exchangeRate = json.exchangeRate.rate
  -- print (string.format("Exchange rate: %s", exchangeRate))

  local securities = {}
  for i, v in pairs(json.position) do
    local security = {}
    security.exchangeRate = exchangeRate

    security.name = v.secDesc
    security.quantity = v.quantity
    security.amount = v.displayPositionBalance.closingMktValue.value
    security.originalCurrencyAmount = v.assetPositionBalance.closingMktValue.value
    security.currencyOfOriginalAmount = originalCurrency
    security.price = v.displayPositionBalance.closingPrice.value

    local totalCostBasis = v.displayPositionBalance.totalCostBasis.value
    if (totalCostBasis) then
      security.purchasePrice = totalCostBasis / security.quantity
    end

    table.insert(securities, security)
  end

  return securities
end

-- Helper function to format a string in Title Case
function titlecase (str)
  local buf = {}
  local inWord = false
  for i = 1, #str do
    local c = string.sub(str, i, i)
    if inWord then
        table.insert(buf, string.lower(c))
      if string.find(c, '%s') then
        inWord = false
      end
    else
      table.insert(buf, string.upper(c))
      inWord = true
    end
  end
  return table.concat(buf)
end

function randomJsessionId ()
  local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  local length = 32
  local randomString = ''

  math.randomseed(os.time())

  charTable = {}
  for c in chars:gmatch"." do
      table.insert(charTable, c)
  end

  for i = 1, length do
      randomString = randomString .. charTable[math.random(1, #charTable)]
  end

  return randomString
end
