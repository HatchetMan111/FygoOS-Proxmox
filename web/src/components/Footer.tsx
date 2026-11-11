export function Footer() {
  return (
    <footer className="footer">
      <div className="footer-links">
        <a href="https://github.com/HatchetMan111/FygoOS-Proxmox" target="_blank" rel="noreferrer">
          GitHub-Repo
        </a>
        <a
          href="https://forum.proxmox.com/threads/install-fydeos-in-proxmox-ve.149345/"
          target="_blank"
          rel="noreferrer"
        >
          Proxmox-Forum-Thread
        </a>
        <a href="https://fydeos.io/download/" target="_blank" rel="noreferrer">
          FydeOS-Downloads
        </a>
        <a href="https://fygonas.com/open-source" target="_blank" rel="noreferrer">
          fygonas.com/open-source
        </a>
      </div>
      <p>
        Inoffizielles Community-Script: Diese Seite und der Installer automatisieren nur die Proxmox-Installation.
        FygoOS/FydeOS ist ein Projekt von Fyde. Alles läuft lokal auf deinem Host – keine Cloud, keine Telemetrie.
      </p>
    </footer>
  )
}
