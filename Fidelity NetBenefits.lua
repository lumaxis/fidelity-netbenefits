WebBanking{
  version     = 0.05,
  url         = "https://nb.fidelity.com/public/nb/worldwide/home?AuthRedUrl=https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PlanSummary",
  services    = {"Fidelity NetBenefits"},
  description = "Get securities and their current value from the Fidelity NetBenefits website"
}

CONSTANTS = {
  homepage = "https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PlanSummary",
  login = "https://login.fidelity.com/ftgw/Fas/Fidelity/PWI/Login/Response/dj.chf.ra/",
  logout = "https://netbenefitsww.fidelity.com/Catalina/LongBeach?Command=LOGOUT&Realm=mybenefitsww",
  overview = "https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PositionSummary?ACCOUNT="
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
  local number = stockPlanAccountLink:match(".+ACCOUNT=(%w+)_MSFT.*")

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

  local connection = Connection()
  local html = HTML(connection:request("GET", CONSTANTS.overview .. account.accountNumber, nil, nil, {["Cookie"] = g_cookies} ))

  local jsonString = html:xpath('/html/head/script[1]'):text()

  return {balance=extractBalance(jsonString), securities=extractSecurities(jsonString)}
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

  local abckCookie = "_abck=AE221C6450B51346A295098A0AB85D16~0~YAAQsgoWAq6B0vtuAQAAxHY3BgONSS+2jGke2RQ8C8fnWj5jOpCc4ZiWmIPTt0yAWTIdKFmmP/8SE+VD0rslSs6AHsuD90DlR3BWF8dqF7Y9fQftomqm21Dgqv1vI2WUYRXHVUb4yFVWCDNaFZn7qIwq9rJIxFk4ishGyivzIX1xXJVYMMWhSZ5SktvubQPuiU2U5OJT15H8gyqhrkiLHDNDRX+/ihCbEZGPy2nwERucaI5xvAIZIAbiMhsvBjAjhyjfAEa9UdYrVH31FmhbqTHUk4EB9FmYFBMw6l7r0Ga+dzXJHESK1SQLC2+x5bK6dqZ4cWAz/mCO~-1~-1~-1; "
  local cookie = "JSESSIONID=" .. randomJsessionId() .. "; " .. abckCookie
  local headers = {
    Cookie = cookie
  }

  return url, content, contentType, headers
end

function extractBalance (jsonString)
  local balance = jsonString:match('.*"fullNetWorthAltCurrency"%s*:%s*"(.-)".*')
  return formatEuropeanCurrencyValueAsFloat(balance)
end

function extractSecurities (jsonString)
  local currency = jsonString:match('"altCurrencyCode":"(%a+)"')
  local originalCurrency = jsonString:match('"recordkeptCurrencyCode":"(%a+)"')
  local exchangeRate = jsonString:match('"balancesView":.-"altCurrencyValue":"(.-)"')
  -- print (string.format("Exchange rate: %s", exchangeRate))

  local securityJsonsIterator = jsonString:gmatch('.-{("secDesc".-"unrealizedGainLoss".-)}.-')
  -- print(string.format("Security JSON Object: %s", securityJsonsIterator))

  -- Iterate over all found string matches and build securites from it
  local securities = {}
  for securityJson in securityJsonsIterator do
    -- print (string.format("Security JSON: %s", securityJson))
    local security = {}
    security.exchangeRate = exchangeRate

    security.name = titlecase(securityJson:match('"secDesc":"(.-)"'))
    security.quantity = removeCommaThousandsDelimiter(securityJson:match('"quantity":"(.-)"'))
    security.amount = convertUsdToAltCurrency(securityJson:match('"closingMktValue":"(.-)"'), exchangeRate)
    security.originalCurrencyAmount = removeCommaThousandsDelimiter(securityJson:match('"closingMktValue":"(.-)"'))
    security.currencyOfOriginalAmount = originalCurrency
    security.price = convertUsdToAltCurrency(securityJson:match('"closingPrice":"(.-)"'), exchangeRate)

    local totalCostBasis = securityJson:match('"totalCostBasis":"(.-)"')
    if (totalCostBasis) then
      security.purchasePrice = convertUsdToAltCurrency(totalCostBasis, exchangeRate) / security.quantity
    end

    table.insert(securities, security)
  end

  return securities
end

function convertUsdToAltCurrency (usdString, exchangeRate)
  return removeCommaThousandsDelimiter(usdString) * exchangeRate
end

-- Format "numbers" in the form of "€ 1.337,42 EUR" as 1337.42
function formatEuropeanCurrencyValueAsFloat (string)
  local formatString = "%d*%.*%d+,%d+"

  -- Uncomment to debug formatting
  -- print(string.format("Formatting currency string %s as float", string))

  local formattedString = string:match(formatString):gsub("%.", ""):gsub(",", ".")

  -- Uncomment to debug formatting
  -- print(string.format("Result: %s", formattedString))

  return formattedString
end

-- Format "numbers" in the form of "1,337.42" as 1337.42
function removeCommaThousandsDelimiter (string)
  local formatString = "%d*,*%d+%.%d+"

  return string:match(formatString):gsub(",", "")
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
