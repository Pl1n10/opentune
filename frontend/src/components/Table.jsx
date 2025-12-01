import { clsx } from 'clsx'

export function Table({ children, className }) {
  return (
    <div className={clsx('overflow-x-auto', className)}>
      <table className="min-w-full divide-y divide-gray-200">
        {children}
      </table>
    </div>
  )
}

export function TableHead({ children }) {
  return (
    <thead className="bg-gray-50">
      {children}
    </thead>
  )
}

export function TableBody({ children }) {
  return (
    <tbody className="bg-white divide-y divide-gray-200">
      {children}
    </tbody>
  )
}

export function TableRow({ children, onClick, className }) {
  return (
    <tr 
      onClick={onClick}
      className={clsx(
        onClick && 'cursor-pointer hover:bg-gray-50',
        className
      )}
    >
      {children}
    </tr>
  )
}

export function TableHeader({ children, className }) {
  return (
    <th className={clsx(
      'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider',
      className
    )}>
      {children}
    </th>
  )
}

export function TableCell({ children, className }) {
  return (
    <td className={clsx('px-6 py-4 whitespace-nowrap text-sm', className)}>
      {children}
    </td>
  )
}
