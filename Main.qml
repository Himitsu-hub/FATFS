import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Window {
    id: window
    width: 1400; height: 900
    visible: true
    title: "Makarov FAT System"
    color: "#050505"

    readonly property int clusterSize: 4096
    readonly property int totalClusters: 100
    readonly property int maxWear: 20
    property string highlightedFileName: ""
    property int editingIndex: -1
    property string editingText: ""
    property var fatTable: []
    property var wearTable: []

    // --- ЛОГИКА ---
    function addLog(msg) {
        let time = new Date().toLocaleTimeString("ru-RU");
        logModel.insert(0, { "timestamp": time, "message": msg });
    }

    function defragmentDisk() {
        addLog("SYSTEM: Запуск дефрагментации...");
        let filesData = [];
        for (let i = 0; i < rootDirectoryModel.count; i++) {
            let file = rootDirectoryModel.get(i);
            if (file.fileName === "ROOT") continue;
            filesData.push({
                idx: i, name: file.fileName, content: file.content,
                size: file.sizeBytes, isDir: file.isDir,
                color: file.fileColor, parent: file.parentFolder
            });
        }

        for (let i = 4; i < totalClusters; i++) fatTable[i] = 0;

        let root = rootDirectoryModel.get(0);
        rootDirectoryModel.clear();
        rootDirectoryModel.append(root);

        filesData.forEach(f => {
            let clustersNeeded = f.isDir ? 1 : Math.ceil(f.size / clusterSize) || 1;
            let found = [];
            for (let i = 0; i < totalClusters && found.length < clustersNeeded; i++) {
                if (fatTable[i] === 0) found.push(i);
            }

            if (found.length === clustersNeeded) {
                for (let i = 0; i < found.length; i++) {
                    let idx = found[i];
                    fatTable[idx] = (i === found.length - 1) ? -1 : found[i+1];
                    wearTable[idx]++;
                }
                rootDirectoryModel.append({
                    "fileName": f.name, "parentFolder": f.parent, "startCluster": found[0],
                    "sizeBytes": f.size, "clusters": clustersNeeded,
                    "isDir": f.isDir, "fileColor": f.color, "content": f.content
                });
            }
        });
        addLog("SYSTEM: Дефрагментация завершена.");
        syncModels();
    }

    function initSystem() {
        let fTable = []; let wTable = [];
        for (let i = 0; i < totalClusters; i++) {
            fTable.push(i < 4 ? -2 : 0);
            wTable.push(0);
        }
        fatTable = fTable; wearTable = wTable;
        rootDirectoryModel.clear();
        highlightedFileName = "";
        addFolderObject("ROOT", "#555555", "");
        allocateEntry("SYSTEM", 0, true, "ROOT", "#ff4444");
        allocateEntry("GAMES", 0, true, "ROOT", "#ffbb00");
        allocateEntry("DOCS", 0, true, "ROOT", "#0088ff");
        addLog("SYSTEM: Инициализация завершена.");
        syncModels();
    }

    function addFolderObject(name, color, parent) {
        rootDirectoryModel.append({
            "fileName": name, "isDir": true, "fileColor": color,
            "parentFolder": parent, "startCluster": -1, "sizeBytes": 0, "clusters": 0, "content": ""
        });
    }

    function allocateEntry(name, sizeInBytes, isDir, targetFolder, forcedColor) {
        let clustersNeeded = isDir ? 1 : Math.ceil(sizeInBytes / clusterSize) || 1;
        let found = findBestClusters(clustersNeeded);
        if (!found) { addLog("ERROR: Нет места или превышен износ!"); return; }

        let parentName = targetFolder || folderSelector.currentText;
        let parentColor = "#555555";
        for(let i=0; i < rootDirectoryModel.count; i++) {
            if(rootDirectoryModel.get(i).fileName === parentName) {
                parentColor = rootDirectoryModel.get(i).fileColor; break;
            }
        }

        let finalColor = forcedColor ? forcedColor :
                        (isDir ? Qt.hsla(Math.random(), 0.6, 0.5, 1.0).toString() : Qt.lighter(parentColor, 1.4).toString());

        for (let i = 0; i < found.length; i++) {
            let idx = found[i];
            fatTable[idx] = (i === found.length - 1) ? -1 : found[i+1];
            wearTable[idx]++;
        }

        rootDirectoryModel.append({
            "fileName": name.toUpperCase(), "parentFolder": parentName, "startCluster": found[0],
            "sizeBytes": isDir ? 0 : sizeInBytes, "clusters": clustersNeeded,
            "isDir": isDir, "fileColor": finalColor, "content": ""
        });
        addLog("OK: Создан " + name);
        syncModels();
    }

    function updateFileContent(modelIdx, newText) {
        let file = rootDirectoryModel.get(modelIdx);
        if (file.isDir) return;
        let newSize = newText.length * 2;
        let newClustersNeeded = Math.ceil(newSize / clusterSize) || 1;
        let currentClusters = file.clusters;

        if (newClustersNeeded > currentClusters) {
            let extraNeeded = newClustersNeeded - currentClusters;
            let found = findBestClusters(extraNeeded);
            if (!found) { addLog("CRITICAL: Нет места!"); return; }
            let curr = file.startCluster;
            while (fatTable[curr] !== -1) { curr = fatTable[curr]; }
            fatTable[curr] = found[0];
            for (let i = 0; i < found.length; i++) {
                let idx = found[i];
                fatTable[idx] = (i === found.length - 1) ? -1 : found[i+1];
                wearTable[idx]++;
            }
        } else if (newClustersNeeded < currentClusters) {
            let curr = file.startCluster;
            for (let i = 1; i < newClustersNeeded; i++) { curr = fatTable[curr]; }
            let toDelete = fatTable[curr];
            fatTable[curr] = -1;
            while (toDelete !== -1 && toDelete > -1) {
                let next = fatTable[toDelete];
                fatTable[toDelete] = 0;
                toDelete = next;
            }
        }
        rootDirectoryModel.setProperty(modelIdx, "content", newText);
        rootDirectoryModel.setProperty(modelIdx, "sizeBytes", newSize);
        rootDirectoryModel.setProperty(modelIdx, "clusters", newClustersNeeded);
        syncModels();
    }

    function findBestClusters(needed) {
        let candidates = [];
        for (let i = 0; i < totalClusters; i++) {
            if (fatTable[i] === 0 && wearTable[i] < maxWear) {
                candidates.push({idx: i, wear: wearTable[i]});
            }
        }
        candidates.sort((a, b) => a.wear - b.wear);
        return candidates.length < needed ? null : candidates.slice(0, needed).map(c => c.idx);
    }

    function deleteFile(idx) {
        let file = rootDirectoryModel.get(idx);
        if (file.fileName === "ROOT") return;
        let curr = file.startCluster;
        while (curr !== -1 && curr > -1) {
            let next = fatTable[curr];
            fatTable[curr] = 0;
            curr = next;
        }
        rootDirectoryModel.remove(idx);
        syncModels();
    }

    function syncModels() {
        diskModel.clear();
        for (let i = 0; i < totalClusters; i++) {
            let val = fatTable[i];
            let isHighlighted = (highlightedFileName === "") || isClusterInObject(i, highlightedFileName);
            let isDirCluster = false;
            for(let j=0; j < rootDirectoryModel.count; j++) {
                let obj = rootDirectoryModel.get(j);
                if (obj.startCluster === i && obj.isDir) { isDirCluster = true; break; }
            }
            diskModel.append({
                "index": i, "value": val, "wear": wearTable[i],
                "clusterColor": val === 0 ? "#1a1a1a" : (val === -2 ? "#333" : findColor(i)),
                "isHighlighted": isHighlighted, "isFolderType": isDirCluster
            });
        }
    }

    function isClusterInObject(clusterIdx, objName) {
        for (let i = 0; i < rootDirectoryModel.count; i++) {
            let obj = rootDirectoryModel.get(i);
            if (obj.fileName === objName || obj.parentFolder === objName) {
                let curr = obj.startCluster;
                while (curr !== -1 && curr > -1) {
                    if (curr === clusterIdx) return true;
                    curr = fatTable[curr];
                }
            }
        }
        return false;
    }

    function findColor(idx) {
        for (let i = 0; i < rootDirectoryModel.count; i++) {
            let f = rootDirectoryModel.get(i);
            let curr = f.startCluster;
            while (curr !== -1 && curr > -1) {
                if (curr === idx) return f.fileColor;
                curr = fatTable[curr];
            }
        }
        return "#00ff88";
    }

    Component.onCompleted: initSystem()

    ListModel { id: diskModel }
    ListModel { id: rootDirectoryModel }
    ListModel { id: logModel }

    Popup {
        id: editorPopup
        anchors.centerIn: parent
        width: 500; height: 450
        modal: true; focus: true
        background: Rectangle { color: "#1a1a1a"; border.color: "#00ccff"; radius: 10 }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 15; spacing: 10
            Text {
                text: "РЕДАКТИРОВАНИЕ: " + (editingIndex >= 0 ? rootDirectoryModel.get(editingIndex).fileName : "")
                color: "#00ccff"; font.bold: true; font.pixelSize: 16
            }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                TextArea {
                    id: editorArea
                    text: editingText; color: "white"; wrapMode: TextArea.Wrap; font.pixelSize: 14
                    padding: 10; selectByMouse: true
                    background: Rectangle { color: "#050505"; radius: 4 }
                }
            }
            Text {
                text: "Размер: " + (editorArea.text.length * 2) + " байт | Нужно кластеров: " + Math.ceil((editorArea.text.length * 2) / clusterSize || 1)
                color: "#00ff88"; font.pixelSize: 11; font.family: "Monospace"
            }
            RowLayout {
                spacing: 10
                Button {
                    text: "СОХРАНИТЬ"; Layout.fillWidth: true
                    onClicked: { updateFileContent(editingIndex, editorArea.text); editorPopup.close(); }
                }
                Button { text: "ОТМЕНА"; onClicked: editorPopup.close() }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 2
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 2

            Rectangle {
                Layout.preferredWidth: 380; Layout.fillHeight: true; color: "#0f0f0f"
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 15; spacing: 10
                    Text { text: "MAKAROV FAT SYSTEM"; color: "#00ccff"; font.bold: true; font.pixelSize: 20 }
                    TextField { id: fName; placeholderText: "Имя..."; Layout.fillWidth: true; color: "white" }
                    RowLayout {
                        Text { text: "Куда:"; color: "#888" }
                        ComboBox {
                            id: folderSelector; Layout.fillWidth: true
                            model: {
                                let folders = [];
                                for(let i=0; i<rootDirectoryModel.count; i++) {
                                    if(rootDirectoryModel.get(i).isDir) folders.push(rootDirectoryModel.get(i).fileName);
                                }
                                return folders;
                            }
                        }
                    }

                    // --- ИСПРАВЛЕННЫЙ БЛОК ВВОДА РАЗМЕРА ---
                    RowLayout {
                        Text { text: "Размер (B):"; color: "#888" }
                        TextField {
                            id: fSizeField
                            text: "4096"
                            placeholderText: "Байт..."
                            Layout.fillWidth: true
                            color: "white"
                            validator: IntValidator { bottom: 1; top: 1000000 }
                            background: Rectangle { color: "#1a1a1a"; border.color: fSizeField.activeFocus ? "#00ccff" : "#333"; radius: 4 }
                        }
                    }

                    RowLayout {
                        Button {
                            text: "📄 ФАЙЛ"; Layout.fillWidth: true
                            onClicked: {
                                let size = parseInt(fSizeField.text) || 0;
                                if (size > 0) allocateEntry(fName.text || "FILE", size, false);
                                else addLog("ERROR: Неверный размер!");
                            }
                        }
                        Button { text: "📁 ПАПКА"; Layout.fillWidth: true; onClicked: allocateEntry(fName.text || "DIR", 0, true) }
                    }
                    // ----------------------------------------

                    RowLayout {
                        Button { text: "🧹 ДЕФРАГМЕНТАЦИЯ"; Layout.fillWidth: true; palette.button: "#004488"; onClicked: defragmentDisk() }
                        Button { text: "🚨 ФОРМАТ"; Layout.preferredWidth: 100; palette.button: "#660000"; onClicked: initSystem() }
                    }
                    Text { text: "ПРОВОДНИК:"; color: "#555"; font.bold: true; Layout.topMargin: 10 }
                    ListView {
                        id: expView; Layout.fillHeight: true; Layout.fillWidth: true; clip: true
                        model: rootDirectoryModel
                        delegate: ItemDelegate {
                            width: expView.width; height: 50
                            onClicked: {
                                if (!model.isDir) { editingIndex = index; editingText = model.content; editorPopup.open(); }
                                highlightedFileName = (highlightedFileName === model.fileName) ? "" : model.fileName;
                                syncModels();
                            }
                            contentItem: Rectangle {
                                color: highlightedFileName === model.fileName ? "#222" : "transparent"; radius: 4
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 5
                                    Text { text: model.isDir ? "📁" : "📄"; font.pixelSize: 16 }
                                    Column {
                                        Layout.fillWidth: true
                                        Text { text: model.fileName; color: "white"; font.bold: true; font.pixelSize: 12 }
                                        Text { text: (model.isDir ? "Папка" : model.sizeBytes + " B"); color: "#666"; font.pixelSize: 9 }
                                    }
                                    Button { text: "DEL"; Layout.preferredWidth: 40; onClicked: deleteFile(index) }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; color: "#050505"
                GridView {
                    id: grid; anchors.fill: parent; anchors.margins: 20
                    cellWidth: 85; cellHeight: 85; model: diskModel
                    delegate: Item {
                        width: 85; height: 85
                        Rectangle {
                            width: 78; height: 78; radius: model.isFolderType ? 20 : 5
                            color: model.clusterColor
                            border.width: model.isHighlighted ? 2 : 1
                            border.color: model.isHighlighted ? "white" : "#222"
                            opacity: model.isHighlighted ? 1.0 : 0.2

                            Text {
                                text: model.index; color: "white"; opacity: 0.4;
                                font.pixelSize: 9; anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 4
                            }

                            Text {
                                anchors.centerIn: parent
                                font.bold: true
                                font.pixelSize: 11
                                color: "white"
                                horizontalAlignment: Text.AlignHCenter
                                text: {
                                    if (model.value === -2) return "SYS";
                                    if (model.value === 0) return "";

                                    let isFirst = false;
                                    for (let i = 0; i < rootDirectoryModel.count; i++) {
                                        if (rootDirectoryModel.get(i).startCluster === model.index) {
                                            isFirst = true; break;
                                        }
                                    }

                                    let content = "";
                                    if (isFirst) content += "START\n";

                                    if (model.value === -1) content += "EOF";
                                    else content += model.value;

                                    return content;
                                }
                            }

                            Text {
                                text: model.isFolderType ? "📁" : (model.value !== 0 && model.value !== -2 ? "📄" : "")
                                font.pixelSize: 10
                                anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 4
                                opacity: 0.7
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 14; anchors.horizontalCenter: parent.horizontalCenter
                                width: 50; height: 3; color: "#333"; radius: 2; visible: (model.value !== 0 && model.value !== -2)
                                Rectangle {
                                    width: (model.wear / maxWear) * parent.width; height: parent.height; radius: 2
                                    color: model.wear > (maxWear * 0.8) ? "#ff4444" : (model.wear > (maxWear * 0.5) ? "#ffbb00" : "#00ff88")
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 150; color: "#0a0a0a"; border.color: "#1a1a1a"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 10
                Text { text: "СИСТЕМНЫЙ ЖУРНАЛ (LOGS)"; color: "#444"; font.pixelSize: 12; font.bold: true }
                ListView {
                    id: logView; Layout.fillWidth: true; Layout.fillHeight: true
                    model: logModel; clip: true
                    delegate: RowLayout {
                        width: logView.width; spacing: 15
                        Text { text: model.timestamp; color: "#00ccff"; font.family: "Courier"; font.pixelSize: 11 }
                        Text { text: model.message; color: "#aaa"; font.pixelSize: 11; Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
