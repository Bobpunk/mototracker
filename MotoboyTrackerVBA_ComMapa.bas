' Módulo VBA para consultar dados do Motoboy Tracker com Mapas Interativos
' Este módulo permite consultar dados e visualizar localizações em mapas
' Requer: Microsoft Internet Explorer para exibir mapas

Option Explicit

' Configurações da API
Private Const API_BASE_URL As String = "https://mototracker-production.up.railway.app/api"

' Função principal para exibir mapa com localização do motoboy
Public Sub ShowMotoboyMap(Optional motoboyId As String = "")
    Dim ws As Worksheet
    Dim jsonData As String
    Dim locations As String
    Dim mapHTML As String
    
    ' Obter dados do motoboy
    If motoboyId = "" Then
        motoboyId = InputBox("Digite o ID do Motoboy:", "Motoboy Tracker", "MOT001")
        If motoboyId = "" Then Exit Sub
    End If
    
    ' Obter localizações
    locations = GetMotoboyLocations(motoboyId)
    
    ' Verificar se há dados
    If Left(locations, 5) = "Erro:" Then
        MsgBox "Erro ao obter localizações: " & locations, vbCritical
        Exit Sub
    End If
    
    ' Gerar HTML do mapa
    mapHTML = GenerateMapHTML(motoboyId, locations)
    
    ' Criar planilha para o mapa
    Set ws = CreateMapWorksheet(motoboyId)
    
    ' Inserir HTML do mapa
    ws.Cells(1, 1).Value = "Mapa do Motoboy: " & motoboyId
    ws.Cells(1, 1).Font.Size = 16
    ws.Cells(1, 1).Font.Bold = True
    
    ' Criar objeto WebBrowser para exibir o mapa
    CreateWebBrowserControl ws, mapHTML
    
    ' Exibir dados em tabela
    DisplayLocationData ws, locations
End Sub

' Função para gerar HTML do mapa interativo
Private Function GenerateMapHTML(motoboyId As String, locationsJSON As String) As String
    Dim html As String
    Dim locations As String
    Dim markers As String
    
    ' Extrair coordenadas do JSON (implementação simplificada)
    locations = ExtractCoordinates(locationsJSON)
    
    ' Gerar marcadores para o mapa
    markers = GenerateMapMarkers(locations)
    
    html = "<!DOCTYPE html>" & vbCrLf
    html = html & "<html>" & vbCrLf
    html = html & "<head>" & vbCrLf
    html = html & "    <meta charset='UTF-8'>" & vbCrLf
    html = html & "    <meta name='viewport' content='width=device-width, initial-scale=1.0'>" & vbCrLf
    html = html & "    <title>Mapa Motoboy " & motoboyId & "</title>" & vbCrLf
    html = html & "    <link rel='stylesheet' href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css' />" & vbCrLf
    html = html & "    <script src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'></script>" & vbCrLf
    html = html & "    <style>" & vbCrLf
    html = html & "        body { margin: 0; padding: 0; font-family: Arial, sans-serif; }" & vbCrLf
    html = html & "        #map { height: 500px; width: 100%; }" & vbCrLf
    html = html & "        .info { padding: 10px; background: #f0f0f0; border-bottom: 1px solid #ccc; }" & vbCrLf
    html = html & "        .info h2 { margin: 0 0 10px 0; color: #333; }" & vbCrLf
    html = html & "        .info p { margin: 5px 0; color: #666; }" & vbCrLf
    html = html & "        .controls { padding: 10px; background: #fff; border-bottom: 1px solid #ccc; }" & vbCrLf
    html = html & "        .btn { padding: 8px 16px; margin: 5px; background: #007bff; color: white; border: none; border-radius: 4px; cursor: pointer; }" & vbCrLf
    html = html & "        .btn:hover { background: #0056b3; }" & vbCrLf
    html = html & "    </style>" & vbCrLf
    html = html & "</head>" & vbCrLf
    html = html & "<body>" & vbCrLf
    html = html & "    <div class='info'>" & vbCrLf
    html = html & "        <h2>🏍️ Motoboy: " & motoboyId & "</h2>" & vbCrLf
    html = html & "        <p>📍 Localização em tempo real</p>" & vbCrLf
    html = html & "        <p>🕒 Última atualização: " & Now() & "</p>" & vbCrLf
    html = html & "    </div>" & vbCrLf
    html = html & "    <div class='controls'>" & vbCrLf
    html = html & "        <button class='btn' onclick='refreshMap()'>🔄 Atualizar</button>" & vbCrLf
    html = html & "        <button class='btn' onclick='centerOnMotoboy()'>🎯 Centralizar</button>" & vbCrLf
    html = html & "        <button class='btn' onclick='showRoute()'>🛣️ Mostrar Rota</button>" & vbCrLf
    html = html & "    </div>" & vbCrLf
    html = html & "    <div id='map'></div>" & vbCrLf
    html = html & "    <script>" & vbCrLf
    html = html & "        let map;" & vbCrLf
    html = html & "        let motoboyMarker;" & vbCrLf
    html = html & "        let routeLayer;" & vbCrLf
    html = html & "        let locations = " & locations & ";" & vbCrLf
    html = html & "        " & vbCrLf
    html = html & "        function initMap() {" & vbCrLf
    html = html & "            // Inicializar mapa" & vbCrLf
    html = html & "            map = L.map('map').setView([-23.5505, -46.6333], 13);" & vbCrLf
    html = html & "            " & vbCrLf
    html = html & "            // Adicionar camada de tiles" & vbCrLf
    html = html & "            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {" & vbCrLf
    html = html & "                attribution: '© OpenStreetMap contributors'" & vbCrLf
    html = html & "            }).addTo(map);" & vbCrLf
    html = html & "            " & vbCrLf
    html = html & "            // Adicionar marcadores" & vbCrLf
    html = html & "            addMarkers();" & vbCrLf
    html = html & "            " & vbCrLf
    html = html & "            // Centralizar no último ponto" & vbCrLf
    html = html & "            if (locations.length > 0) {" & vbCrLf
    html = html & "                const lastLocation = locations[locations.length - 1];" & vbCrLf
    html = html & "                map.setView([lastLocation.lat, lastLocation.lng], 15);" & vbCrLf
    html = html & "            }" & vbCrLf
    html = html & "        }" & vbCrLf
    html = html & "        " & vbCrLf
    html = html & "        function addMarkers() {" & vbCrLf
    html = html & "            locations.forEach((location, index) => {" & vbCrLf
    html = html & "                const marker = L.marker([location.lat, location.lng])" & vbCrLf
    html = html & "                    .addTo(map)" & vbCrLf
    html = html & "                    .bindPopup(`" & vbCrLf
    html = html & "                        <b>Motoboy " & motoboyId & "</b><br>" & vbCrLf
    html = html & "                        📍 Lat: ${location.lat.toFixed(6)}<br>" & vbCrLf
    html = html & "                        📍 Lng: ${location.lng.toFixed(6)}<br>" & vbCrLf
    html = html & "                        🎯 Precisão: ${location.accuracy}m<br>" & vbCrLf
    html = html & "                        🕒 ${new Date(location.timestamp).toLocaleString()}" & vbCrLf
    html = html & "                    `);" & vbCrLf
    html = html & "                " & vbCrLf
    html = html & "                // Destacar último ponto" & vbCrLf
    html = html & "                if (index === locations.length - 1) {" & vbCrLf
    html = html & "                    marker.setIcon(L.divIcon({" & vbCrLf
    html = html & "                        html: '🏍️'," & vbCrLf
    html = html & "                        iconSize: [30, 30]," & vbCrLf
    html = html & "                        className: 'motoboy-icon'" & vbCrLf
    html = html & "                    }));" & vbCrLf
    html = html & "                    motoboyMarker = marker;" & vbCrLf
    html = html & "                }" & vbCrLf
    html = html & "            });" & vbCrLf
    html = html & "        }" & vbCrLf
    html = html & "        " & vbCrLf
    html = html & "        function refreshMap() {" & vbCrLf
    html = html & "            location.reload();" & vbCrLf
    html = html & "        }" & vbCrLf
    html = html & "        " & vbCrLf
    html = html & "        function centerOnMotoboy() {" & vbCrLf
    html = html & "            if (motoboyMarker) {" & vbCrLf
    html = html & "                map.setView(motoboyMarker.getLatLng(), 15);" & vbCrLf
    html = html & "                motoboyMarker.openPopup();" & vbCrLf
    html = html & "            }" & vbCrLf
    html = html & "        }" & vbCrLf
    html = html & "        " & vbCrLf
    html = html & "        function showRoute() {" & vbCrLf
    html = html & "            if (routeLayer) {" & vbCrLf
    html = html & "                map.removeLayer(routeLayer);" & vbCrLf
    html = html & "                routeLayer = null;" & vbCrLf
    html = html & "            } else {" & vbCrLf
    html = html & "                const points = locations.map(loc => [loc.lat, loc.lng]);" & vbCrLf
    html = html & "                routeLayer = L.polyline(points, {color: 'red', weight: 3}).addTo(map);" & vbCrLf
    html = html & "            }" & vbCrLf
    html = html & "        }" & vbCrLf
    html = html & "        " & vbCrLf
    html = html & "        // Inicializar mapa quando a página carregar" & vbCrLf
    html = html & "        window.onload = initMap;" & vbCrLf
    html = html & "    </script>" & vbCrLf
    html = html & "</body>" & vbCrLf
    html = html & "</html>" & vbCrLf
    
    GenerateMapHTML = html
End Function

' Função para extrair coordenadas do JSON
Private Function ExtractCoordinates(jsonData As String) As String
    ' Implementação simplificada para extrair coordenadas
    ' Em uma implementação completa, use uma biblioteca JSON para VBA
    Dim result As String
    Dim lines As Variant
    Dim i As Integer
    Dim line As String
    Dim lat As String
    Dim lng As String
    Dim timestamp As String
    
    result = "["
    lines = Split(jsonData, vbCrLf)
    
    For i = 0 To UBound(lines)
        line = Trim(lines(i))
        If InStr(line, "latitude") > 0 Then
            lat = ExtractValue(line, "latitude")
        ElseIf InStr(line, "longitude") > 0 Then
            lng = ExtractValue(line, "longitude")
        ElseIf InStr(line, "timestamp") > 0 Then
            timestamp = ExtractValue(line, "timestamp")
            
            If lat <> "" And lng <> "" Then
                If result <> "[" Then result = result & ","
                result = result & "{" & _
                    """lat"": " & lat & ", " & _
                    """lng"": " & lng & ", " & _
                    """accuracy"": 10, " & _
                    """timestamp"": """ & timestamp & """" & _
                    "}"
                lat = ""
                lng = ""
                timestamp = ""
            End If
        End If
    Next i
    
    result = result & "]"
    ExtractCoordinates = result
End Function

' Função auxiliar para extrair valores do JSON
Private Function ExtractValue(jsonLine As String, key As String) As String
    Dim startPos As Integer
    Dim endPos As Integer
    Dim value As String
    
    startPos = InStr(jsonLine, """" & key & """")
    If startPos > 0 Then
        startPos = InStr(startPos, ":")
        If startPos > 0 Then
            startPos = startPos + 1
            Do While Mid(jsonLine, startPos, 1) = " " Or Mid(jsonLine, startPos, 1) = Chr(9)
                startPos = startPos + 1
            Loop
            
            If Mid(jsonLine, startPos, 1) = """" Then
                startPos = startPos + 1
                endPos = InStr(startPos, jsonLine, """")
            Else
                endPos = InStr(startPos, jsonLine, ",")
                If endPos = 0 Then endPos = InStr(startPos, jsonLine, "}")
            End If
            
            If endPos > startPos Then
                value = Mid(jsonLine, startPos, endPos - startPos)
                value = Replace(value, """", "")
                ExtractValue = value
            End If
        End If
    End If
End Function

' Função para gerar marcadores do mapa
Private Function GenerateMapMarkers(locations As String) As String
    ' Esta função seria usada para gerar marcadores personalizados
    ' Implementação simplificada
    GenerateMapMarkers = locations
End Function

' Função para criar planilha do mapa
Private Function CreateMapWorksheet(motoboyId As String) As Worksheet
    Dim ws As Worksheet
    
    ' Criar ou limpar planilha
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets("Mapa_" & motoboyId)
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add
        ws.Name = "Mapa_" & motoboyId
    End If
    On Error GoTo 0
    
    ' Limpar planilha
    ws.Cells.Clear
    
    Set CreateMapWorksheet = ws
End Function

' Função para criar controle WebBrowser
Private Sub CreateWebBrowserControl(ws As Worksheet, htmlContent As String)
    ' Salvar HTML em arquivo temporário
    Dim tempFile As String
    Dim fileNum As Integer
    
    tempFile = Environ("TEMP") & "\motoboy_map_" & Format(Now, "yyyymmdd_hhmmss") & ".html"
    
    fileNum = FreeFile
    Open tempFile For Output As #fileNum
    Print #fileNum, htmlContent
    Close #fileNum
    
    ' Exibir arquivo no navegador padrão
    Shell "explorer.exe """ & tempFile & """", vbNormalFocus
End Sub

' Função para exibir dados de localização em tabela
Private Sub DisplayLocationData(ws As Worksheet, locationsJSON As String)
    Dim row As Integer
    Dim lines As Variant
    Dim i As Integer
    Dim line As String
    
    row = 3
    ws.Cells(row, 1).Value = "Dados de Localização:"
    ws.Cells(row, 1).Font.Bold = True
    row = row + 1
    
    ' Cabeçalhos da tabela
    ws.Cells(row, 1).Value = "Data/Hora"
    ws.Cells(row, 2).Value = "Latitude"
    ws.Cells(row, 3).Value = "Longitude"
    ws.Cells(row, 4).Value = "Precisão (m)"
    ws.Cells(row, 5).Value = "Endereço"
    
    ' Formatar cabeçalhos
    With ws.Range("A" & row & ":E" & row)
        .Font.Bold = True
        .Interior.Color = RGB(200, 200, 200)
    End With
    
    row = row + 1
    
    ' Exibir dados (implementação simplificada)
    ws.Cells(row, 1).Value = "Dados JSON:"
    ws.Cells(row + 1, 1).Value = locationsJSON
    
    ' Ajustar largura das colunas
    ws.Columns.AutoFit
End Sub

' Função para obter localizações via API
Public Function GetMotoboyLocations(motoboyId As String, Optional startDate As String = "", Optional endDate As String = "") As String
    Dim http As Object
    Dim url As String
    Dim response As String
    
    ' Construir URL da API
    url = API_BASE_URL & "/locations/" & motoboyId
    
    If startDate <> "" And endDate <> "" Then
        url = url & "?start_date=" & startDate & "&end_date=" & endDate
    End If
    
    ' Criar objeto HTTP
    Set http = CreateObject("MSXML2.XMLHTTP")
    
    ' Fazer requisição GET
    http.Open "GET", url, False
    http.send
    
    ' Verificar se a requisição foi bem-sucedida
    If http.Status = 200 Then
        response = http.responseText
    Else
        response = "Erro: " & http.Status & " - " & http.statusText
    End If
    
    GetMotoboyLocations = response
End Function

' Função para testar conectividade
Public Function TestAPIConnection() As Boolean
    Dim http As Object
    Dim url As String
    
    url = API_BASE_URL & "/motoboys"
    
    On Error GoTo ErrorHandler
    
    Set http = CreateObject("MSXML2.XMLHTTP")
    http.Open "GET", url, False
    http.send
    
    If http.Status = 200 Then
        TestAPIConnection = True
    Else
        TestAPIConnection = False
    End If
    
    Exit Function
    
ErrorHandler:
    TestAPIConnection = False
End Function

' Função para exibir mapa de todos os motoboys
Public Sub ShowAllMotoboysMap()
    Dim ws As Worksheet
    Dim jsonData As String
    Dim mapHTML As String
    
    ' Obter dados de todos os motoboys
    jsonData = GetMotoboyData("")
    
    ' Gerar HTML do mapa
    mapHTML = GenerateAllMotoboysMapHTML(jsonData)
    
    ' Criar planilha para o mapa
    Set ws = CreateMapWorksheet("Todos")
    
    ' Exibir mapa
    ws.Cells(1, 1).Value = "Mapa de Todos os Motoboys"
    ws.Cells(1, 1).Font.Size = 16
    ws.Cells(1, 1).Font.Bold = True
    
    CreateWebBrowserControl ws, mapHTML
End Sub

' Função para gerar mapa de todos os motoboys
Private Function GenerateAllMotoboysMapHTML(jsonData As String) As String
    Dim html As String
    
    html = "<!DOCTYPE html>" & vbCrLf
    html = html & "<html>" & vbCrLf
    html = html & "<head>" & vbCrLf
    html = html & "    <meta charset='UTF-8'>" & vbCrLf
    html = html & "    <title>Mapa de Todos os Motoboys</title>" & vbCrLf
    html = html & "    <link rel='stylesheet' href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css' />" & vbCrLf
    html = html & "    <script src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'></script>" & vbCrLf
    html = html & "    <style>" & vbCrLf
    html = html & "        body { margin: 0; padding: 0; font-family: Arial, sans-serif; }" & vbCrLf
    html = html & "        #map { height: 600px; width: 100%; }" & vbCrLf
    html = html & "        .info { padding: 10px; background: #f0f0f0; border-bottom: 1px solid #ccc; }" & vbCrLf
    html = html & "    </style>" & vbCrLf
    html = html & "</head>" & vbCrLf
    html = html & "<body>" & vbCrLf
    html = html & "    <div class='info'>" & vbCrLf
    html = html & "        <h2>🏍️ Mapa de Todos os Motoboys</h2>" & vbCrLf
    html = html & "        <p>📍 Localizações em tempo real</p>" & vbCrLf
    html = html & "    </div>" & vbCrLf
    html = html & "    <div id='map'></div>" & vbCrLf
    html = html & "    <script>" & vbCrLf
    html = html & "        let map = L.map('map').setView([-23.5505, -46.6333], 11);" & vbCrLf
    html = html & "        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {" & vbCrLf
    html = html & "            attribution: '© OpenStreetMap contributors'" & vbCrLf
    html = html & "        }).addTo(map);" & vbCrLf
    html = html & "    </script>" & vbCrLf
    html = html & "</body>" & vbCrLf
    html = html & "</html>" & vbCrLf
    
    GenerateAllMotoboysMapHTML = html
End Function

' Função para obter dados gerais
Public Function GetMotoboyData(Optional motoboyId As String = "", Optional startDate As String = "", Optional endDate As String = "") As String
    Dim http As Object
    Dim url As String
    Dim response As String
    
    ' Construir URL da API
    url = API_BASE_URL & "/report"
    
    If startDate <> "" And endDate <> "" Then
        url = url & "?start_date=" & startDate & "&end_date=" & endDate
    End If
    
    ' Criar objeto HTTP
    Set http = CreateObject("MSXML2.XMLHTTP")
    
    ' Fazer requisição GET
    http.Open "GET", url, False
    http.send
    
    ' Verificar se a requisição foi bem-sucedida
    If http.Status = 200 Then
        response = http.responseText
    Else
        response = "Erro: " & http.Status & " - " & http.statusText
    End If
    
    GetMotoboyData = response
End Function
