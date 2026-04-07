import { createContext, useContext, useState } from 'react'
import es from './es.js'
import en from './en.js'
import it from './it.js'

const translations = { es, en, it }

const LangContext = createContext(null)

export function LangProvider({ children }) {
  const stored = localStorage.getItem('mr_lang') || 'es'
  const [lang, setLangState] = useState(stored)

  function setLang(l) {
    localStorage.setItem('mr_lang', l)
    setLangState(l)
  }

  const t = translations[lang] || translations.es

  return (
    <LangContext.Provider value={{ lang, setLang, t, langs: ['es', 'en', 'it'] }}>
      {children}
    </LangContext.Provider>
  )
}

export function useLang() {
  return useContext(LangContext)
}

// Language display names
export const LANG_NAMES = {
  es: '🇪🇸 Español',
  en: '🇬🇧 English',
  it: '🇮🇹 Italiano',
}
