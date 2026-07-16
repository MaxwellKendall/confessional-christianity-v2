// Content pages (sessions, worship, reading, browse) keep the mockups'
// single centered column; the shell itself is full-bleed, so the column is
// a reading measure on the page, not a framed card.
export default function ColumnLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <div className="mx-auto flex w-full max-w-[44rem] flex-1 flex-col">
      {children}
    </div>
  );
}
