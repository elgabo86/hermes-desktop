// splash.js — Mini-app Electron pour afficher la progression de l'auto-update
// Lancé par auto-update.sh via le binaire Electron de l'AppImage (hardlink dans
// un dossier dédié avec son propre resources/app.asar).
// Lit les messages JSON ligne par ligne depuis un FIFO passé en argument.

const { app, BrowserWindow } = require('electron')
const fs = require('node:fs')
const path = require('node:path')

const fifo = process.argv.find(a => a.startsWith('/tmp/hermes-splash')) || '/tmp/hermes-splash.fifo'

app.disableHardwareAcceleration()
app.commandLine.appendSwitch('no-sandbox')

let win

app.whenReady().then(() => {
  win = new BrowserWindow({
    width: 380,
    height: 200,
    frame: false,
    transparent: true,
    resizable: false,
    minimizable: false,
    maximizable: false,
    center: true,
    show: true,
    alwaysOnTop: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    },
  })

  win.loadFile(path.join(__dirname, 'splash.html'))
  win.setMenuBarVisibility(false)

  let buf = ''
  const stream = fs.createReadStream(fifo, { encoding: 'utf8' })
  stream.on('data', (chunk) => {
    buf += chunk
    const lines = buf.split('\n')
    buf = lines.pop()
    for (const line of lines) {
      if (!line.trim()) continue
      try {
        const msg = JSON.parse(line)
        if (win && !win.isDestroyed()) {
          win.webContents.send('update-status', msg)
        }
      } catch (e) {}
    }
  })
  stream.on('end', () => {
    if (win && !win.isDestroyed()) win.close()
    app.quit()
  })
  stream.on('error', () => {
    app.quit()
  })
})

app.on('window-all-closed', () => app.quit())
