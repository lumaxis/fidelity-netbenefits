WebBanking{version     = 0.01,
           url         = "https://nb.fidelity.com/public/nb/worldwide/home",
           services    = {"Fidelity NetBenefits"}}

CONSTANTS = {
  homepage = "https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PlanSummary",
  login = "https://login.fidelity.com/ftgw/Fas/Fidelity/IspCust/Login/Response?AuthRedUrl=https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PlanSummary",
  logout = "https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PlanSummary/Catalina/LongBeach?Command=LOGOUT&amp;Realm=mybenefitsww",
  overview = "https://netbenefitsww.fidelity.com/mybenefitsww/stockplans/navigation/PositionSummary?ACCOUNT="
}

local g_cookies

function SupportsBank (protocol, bankCode)
  bankSupported = (protocol == ProtocolWebBanking) and (bankCode == services[1])
  return bankSupported
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
  connection = Connection()
  html = HTML(connection:get(url))

  url, postContent, postContentType = loginPostRequest(username, password)
  connection:request("POST", url, postContent, postContentType)
  g_cookies = connection:getCookies()
end

function ListAccounts (knownAccounts)
  connection = Connection()

  html = HTML(connection:request("GET", CONSTANTS.homepage, nil, nil, {["Cookie"] = g_cookies} ))

  local accoutName = html:xpath('//*[@id="tile3"]/h2'):text()
  local number = html:xpath('//*[@id="tile3"]/div[2]'):text()

  local stockPlanAccountLink = html:xpath('//*[@id="desktop-stop-propogation"]'):attr("href")
  print(stockPlanAccountLink)
  local subAccount = stockPlanAccountLink:match(".+ACCOUNT=(%w+)")
  print(subAccount)

  local account = {
    name = accoutName,
    accountNumber = number,
    subAccount = subAccount,
    portfolio = true,
    currency = "EUR",
    type = AccountTypePortfolio
  }
  return {account}
end

function RefreshAccount (account, since)
  connection = Connection()
  html = HTML(connection:request("GET", CONSTANTS.overview .. account.subAccount, nil, nil, {["Cookie"] = g_cookies} ))

  securities = html:xpath('//[@class="fund-category"]')
  securities:each(function (index, element)
    print(element:xpath('//a[@firstQuoteLink="symbol-1"]'):text())
  end)

  local security = {
    bookingDate = 1325764800,
    purpose = "Hello World!",
    amount = 42.00
  }

  balanceString = html:xpath('/html/head/script[1]'):attr("type") 

  print(balanceString)
  balance = formatValueString(balanceString)
  print(balance)

  return {balance=balance, securities={security}}
end

function EndSession ()
  connection = Connection()
  html = HTML(connection:get(CONSTANTS.logout))
end

function loginPostRequest (username, password)
  defaultDevicePrint = "version%3D1%26pm_fpua%3Dmozilla%2F5.0+%28macintosh%3B+intel+mac+os+x+10_11_6%29+applewebkit%2F537.36+%28khtml%2C+like+gecko%29+chrome%2F53.0.2785.80+safari%2F537.36%7C5.0+%28Macintosh%3B+Intel+Mac+OS+X+10_11_6%29+AppleWebKit%2F537.36+%28KHTML%2C+like+Gecko%29+Chrome%2F53.0.2785.80+Safari%2F537.36%7CMacIntel%7Cen-US%26pm_fpsc%3D24%7C1440%7C900%7C900%26pm_fpsw%3D%26pm_fptz%3D2%26pm_fpln%3Dlang%3Den-US%7Csyslang%3D%7Cuserlang%3D%26pm_fpjv%3D0%26pm_fpco%3D1" 

  url = CONSTANTS.login
  devicePrint = defaultDevicePrint
  content = "ssn=" .. username .. "&userid=" .. username .. "&SavedIdInd=N&DEVICE_PRINT=" .. devicePrint .. "&ssnt=*********&pin=" .. password .. "&login-btn=Log+In"
  contentType = "application/x-www-form-urlencoded; charset=UTF-8"
  return url, content, contentType
end

function formatValueString(string)
  formatString = "%d*%p-%d+,%d+"
  
  return string:match(formatString):gsub("%.", ""):gsub(",", ".")
end