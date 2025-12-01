import { useState, useEffect, useCallback } from 'react'
import { 
  GitBranch, 
  Plus, 
  Search, 
  Pencil,
  Trash2,
  RefreshCw,
  ExternalLink,
  AlertTriangle,
  FileCode
} from 'lucide-react'
import { repositoriesApi } from '../api/client'
import { 
  Card, 
  PageHeader, 
  Button, 
  LoadingSpinner,
  EmptyState,
  Input
} from '../components/ui'
import { Table, TableHead, TableBody, TableRow, TableHeader, TableCell } from '../components/Table'
import { Modal, ModalFooter } from '../components/Modal'

export default function RepositoriesPage() {
  const [repositories, setRepositories] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  
  // Modal state
  const [showModal, setShowModal] = useState(false)
  const [editingRepo, setEditingRepo] = useState(null)
  const [formData, setFormData] = useState({
    name: '',
    url: '',
    default_branch: 'main',
  })
  const [formError, setFormError] = useState('')
  const [isSaving, setIsSaving] = useState(false)
  
  // Delete modal
  const [showDeleteModal, setShowDeleteModal] = useState(false)
  const [deletingRepo, setDeletingRepo] = useState(null)
  const [isDeleting, setIsDeleting] = useState(false)

  const loadData = useCallback(async () => {
    setIsLoading(true)
    try {
      const data = await repositoriesApi.list()
      setRepositories(data)
    } catch (err) {
      console.error('Failed to load repositories:', err)
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    loadData()
  }, [loadData])

  const openCreateModal = () => {
    setEditingRepo(null)
    setFormData({
      name: '',
      url: '',
      default_branch: 'main',
    })
    setFormError('')
    setShowModal(true)
  }

  const openEditModal = (repo) => {
    setEditingRepo(repo)
    setFormData({
      name: repo.name,
      url: repo.url,
      default_branch: repo.default_branch,
    })
    setFormError('')
    setShowModal(true)
  }

  const handleSave = async () => {
    // Validation
    if (!formData.name.trim()) {
      setFormError('Name is required')
      return
    }
    if (!formData.url.trim()) {
      setFormError('URL is required')
      return
    }
    if (!formData.url.startsWith('http://') && !formData.url.startsWith('https://')) {
      setFormError('URL must start with http:// or https://')
      return
    }

    setIsSaving(true)
    setFormError('')

    try {
      const payload = {
        name: formData.name.trim(),
        url: formData.url.trim(),
        default_branch: formData.default_branch.trim() || 'main',
      }

      if (editingRepo) {
        const updated = await repositoriesApi.update(editingRepo.id, payload)
        setRepositories(prev => prev.map(r => r.id === editingRepo.id ? updated : r))
      } else {
        const created = await repositoriesApi.create(payload)
        setRepositories(prev => [...prev, created])
      }
      
      setShowModal(false)
    } catch (err) {
      setFormError(err.message || 'Failed to save repository')
    } finally {
      setIsSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!deletingRepo) return
    
    setIsDeleting(true)
    try {
      await repositoriesApi.delete(deletingRepo.id)
      setRepositories(prev => prev.filter(r => r.id !== deletingRepo.id))
      setShowDeleteModal(false)
      setDeletingRepo(null)
    } catch (err) {
      console.error('Failed to delete repository:', err)
      setFormError(err.message)
    } finally {
      setIsDeleting(false)
    }
  }

  const filteredRepos = repositories.filter(repo =>
    repo.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    repo.url.toLowerCase().includes(searchQuery.toLowerCase())
  )

  // Extract domain from URL for display (hide credentials)
  const getDisplayUrl = (url) => {
    try {
      const parsed = new URL(url)
      // Hide credentials if present
      if (parsed.username) {
        return `${parsed.protocol}//${parsed.host}${parsed.pathname}`
      }
      return url
    } catch {
      return url
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader 
        title="Repositories"
        description="Manage Git repositories containing DSC configurations"
        action={
          <Button onClick={openCreateModal}>
            <Plus className="w-4 h-4" />
            Add Repository
          </Button>
        }
      />

      {/* Search */}
      <div className="flex items-center gap-4">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search repositories..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
          />
        </div>
        <Button variant="secondary" onClick={loadData}>
          <RefreshCw className="w-4 h-4" />
        </Button>
      </div>

      {/* Repositories Table */}
      <Card>
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner />
          </div>
        ) : filteredRepos.length === 0 ? (
          <EmptyState
            icon={GitBranch}
            title={searchQuery ? 'No repositories found' : 'No repositories yet'}
            description={searchQuery ? 'Try a different search term' : 'Add a Git repository to start defining policies'}
            action={!searchQuery && (
              <Button onClick={openCreateModal}>
                <Plus className="w-4 h-4" />
                Add Repository
              </Button>
            )}
          />
        ) : (
          <Table>
            <TableHead>
              <TableRow>
                <TableHeader>Name</TableHeader>
                <TableHeader>URL</TableHeader>
                <TableHeader>Default Branch</TableHeader>
                <TableHeader>Policies</TableHeader>
                <TableHeader></TableHeader>
              </TableRow>
            </TableHead>
            <TableBody>
              {filteredRepos.map((repo) => (
                <TableRow key={repo.id}>
                  <TableCell>
                    <div className="flex items-center gap-3">
                      <div className="p-2 rounded-lg bg-purple-100">
                        <GitBranch className="w-4 h-4 text-purple-600" />
                      </div>
                      <span className="font-medium text-gray-900">{repo.name}</span>
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <code className="text-xs text-gray-600 max-w-xs truncate">
                        {getDisplayUrl(repo.url)}
                      </code>
                      <a 
                        href={getDisplayUrl(repo.url)} 
                        target="_blank" 
                        rel="noopener noreferrer"
                        className="text-gray-400 hover:text-gray-600"
                      >
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    </div>
                  </TableCell>
                  <TableCell>
                    <code className="text-xs bg-gray-100 px-1.5 py-0.5 rounded">
                      {repo.default_branch}
                    </code>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1.5 text-gray-600">
                      <FileCode className="w-4 h-4 text-gray-400" />
                      {repo.policies_count || 0}
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <Button 
                        variant="ghost" 
                        size="sm"
                        onClick={() => openEditModal(repo)}
                      >
                        <Pencil className="w-4 h-4" />
                      </Button>
                      <Button 
                        variant="ghost" 
                        size="sm"
                        onClick={() => {
                          setDeletingRepo(repo)
                          setShowDeleteModal(true)
                        }}
                      >
                        <Trash2 className="w-4 h-4 text-red-500" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      {/* Create/Edit Modal */}
      <Modal
        isOpen={showModal}
        onClose={() => setShowModal(false)}
        title={editingRepo ? 'Edit Repository' : 'Add Repository'}
      >
        <div className="space-y-4">
          <Input
            label="Name"
            placeholder="e.g., security-baseline, company-dsc-configs"
            value={formData.name}
            onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
          />
          
          <Input
            label="Git URL"
            placeholder="https://github.com/org/repo.git"
            value={formData.url}
            onChange={(e) => setFormData(prev => ({ ...prev, url: e.target.value }))}
          />
          <p className="text-xs text-gray-500 -mt-2">
            For private repos, include credentials: https://user:token@github.com/org/repo.git
          </p>
          
          <Input
            label="Default Branch"
            placeholder="main"
            value={formData.default_branch}
            onChange={(e) => setFormData(prev => ({ ...prev, default_branch: e.target.value }))}
          />

          {formError && (
            <p className="text-sm text-red-600">{formError}</p>
          )}

          <ModalFooter>
            <Button variant="secondary" onClick={() => setShowModal(false)}>
              Cancel
            </Button>
            <Button onClick={handleSave} isLoading={isSaving}>
              {editingRepo ? 'Save Changes' : 'Add Repository'}
            </Button>
          </ModalFooter>
        </div>
      </Modal>

      {/* Delete Modal */}
      <Modal
        isOpen={showDeleteModal}
        onClose={() => {
          setShowDeleteModal(false)
          setFormError('')
        }}
        title="Delete Repository"
      >
        <div className="space-y-4">
          <div className="flex items-center gap-3 p-4 bg-red-50 rounded-lg">
            <AlertTriangle className="w-6 h-6 text-red-600 flex-shrink-0" />
            <div>
              <p className="font-medium text-red-900">Delete "{deletingRepo?.name}"?</p>
              <p className="text-sm text-red-700">
                {deletingRepo?.policies_count > 0 
                  ? `This repository has ${deletingRepo.policies_count} policies. Delete them first.`
                  : 'This action cannot be undone.'
                }
              </p>
            </div>
          </div>
          
          {formError && (
            <p className="text-sm text-red-600">{formError}</p>
          )}
          
          <ModalFooter>
            <Button variant="secondary" onClick={() => {
              setShowDeleteModal(false)
              setFormError('')
            }}>
              Cancel
            </Button>
            <Button 
              variant="danger" 
              onClick={handleDelete} 
              isLoading={isDeleting}
              disabled={deletingRepo?.policies_count > 0}
            >
              Delete Repository
            </Button>
          </ModalFooter>
        </div>
      </Modal>
    </div>
  )
}
