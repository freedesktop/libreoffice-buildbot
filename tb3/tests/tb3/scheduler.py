#! /usr/bin/env python3
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

import datetime
import sh
import unittest
import sys

sys.path.append('./dist-packages')
sys.path.append('./tests')
import helpers
import tb3.scheduler
import tb3.repostate

class TestScheduler(unittest.TestCase):
    def __resolve_ref(self, refname):
        return self.git('show-ref', refname).split(' ')[0]
    def _show_log(self, commit):
        for line in self.git("log", "--pretty=oneline", commit):
            sys.stdout.write(line)
        print()
    def _show_proposals(self, proposals):
        for proposal in proposals:
            sys.stdout.write("%f %s %s" %(proposal.score, proposal.scheduler, self.git("log", "-1", "--pretty=oneline",  proposal.commit)))
        print()
    def _get_best_proposal(self, scheduler, time, expected_message, expected_count, expect_in_order):
        proposals = scheduler.get_proposals(time)
        self.assertEqual(len(proposals), expected_count)
        proposals = sorted(proposals, key = lambda proposal: -proposal.score)
        #self._show_proposals(proposals)
        if expect_in_order:
            for idx in range(len(proposals)-1):
                self.assertEqual(self.git('merge-base', '--is-ancestor', proposals[idx+1].commit, proposals[idx].commit, _ok_code=[0,1]).exit_code, 0)
        commit_msg = ''.join([line for line in self.git("log", "-1", "--pretty=%s",  proposals[0].commit)]).strip('\n')
        self.assertRegex(commit_msg, expected_message)
        return proposals[0]
    def setUp(self):
        (self.testdir, self.git) = helpers.createTestRepo()
        self.state = tb3.repostate.RepoState('linux', 'master', self.testdir)
        self.repohistory = tb3.repostate.RepoHistory('linux', self.testdir)
        self.updater = tb3.repostate.RepoStateUpdater('linux', 'master', self.testdir)
        self.head = self.state.get_head()
        self.preb1 = self.__resolve_ref('refs/tags/pre-branchoff-1')
        self.preb2 = self.__resolve_ref('refs/tags/pre-branchoff-2')
        self.bp = self.__resolve_ref('refs/tags/branchpoint')
        self.postb1 = self.__resolve_ref('refs/tags/post-branchoff-1')
        self.postb2 = self.__resolve_ref('refs/tags/post-branchoff-2')
    def tearDown(self):
        sh.rm('-r', self.testdir)

class TestHeadScheduler(TestScheduler):
    def test_with_running(self):
        #self._show_log(self.head)
        self.scheduler = tb3.scheduler.HeadScheduler('linux', 'master', self.testdir)
        self.state.set_last_good(self.preb1)
        now = datetime.datetime.now()
        best_proposal = self._get_best_proposal(self.scheduler, now, 'commit 9', 9, True)
        self.assertEqual(best_proposal.scheduler, 'HeadScheduler')
        self.assertEqual(best_proposal.commit, self.head)
        self.assertEqual(best_proposal.score, 9)
        self.updater.set_scheduled(best_proposal.commit, 'box', datetime.timedelta(hours=2))
        best_proposal = self._get_best_proposal(self.scheduler, now, 'commit [45]', 9, False)
        self.assertEqual(best_proposal.scheduler, 'HeadScheduler')
        precommits = self.scheduler.count_commits(self.preb1, best_proposal.commit)
        postcommits = self.scheduler.count_commits(best_proposal.commit, self.head)
        self.assertLessEqual(abs(precommits-postcommits),1)
        self.updater.set_scheduled(best_proposal.commit, 'box', datetime.timedelta(hours=2))
        last_proposal = best_proposal
        best_proposal = self._get_best_proposal(self.scheduler, now, 'commit [27]', 9, False)
    def test_with_should_have_finished(self):
        #self._show_log(self.head)
        self.scheduler = tb3.scheduler.HeadScheduler('linux', 'master', self.testdir)
        self.state.set_last_good(self.preb1)
        intwohours = datetime.datetime.now()+datetime.timedelta(hours=2)
        best_proposal = self._get_best_proposal(self.scheduler, intwohours, 'commit 9', 9, True)
        self.assertEqual(best_proposal.scheduler, 'HeadScheduler')
        self.assertEqual(best_proposal.commit, self.head)
        self.assertEqual(best_proposal.score, 9)
        self.updater.set_scheduled(best_proposal.commit, 'box', datetime.timedelta(hours=1))
        best_proposal = self._get_best_proposal(self.scheduler, intwohours, 'commit 5', 9, False)
        self.assertEqual(best_proposal.scheduler, 'HeadScheduler')
        precommits = self.scheduler.count_commits(self.preb1, best_proposal.commit)
        postcommits = self.scheduler.count_commits(best_proposal.commit, self.head)
        self.assertLessEqual(abs(precommits-postcommits),1)
        self.updater.set_scheduled(best_proposal.commit, 'box', datetime.timedelta(hours=1))
        last_proposal = best_proposal
        best_proposal = self._get_best_proposal(self.scheduler, intwohours, 'commit 7', 9, False)
        self.assertEqual(best_proposal.scheduler, 'HeadScheduler')
 
class TestBisectScheduler(TestScheduler):
    def test_get_proposals(self):
        self.state.set_last_good(self.preb1)
        self.state.set_first_bad(self.postb2)
        self.state.set_last_bad(self.postb2)
        self.scheduler = tb3.scheduler.BisectScheduler('linux', 'master', self.testdir)
        best_proposal = self._get_best_proposal(self.scheduler, datetime.datetime.now(), 'commit [45]', 8, False)
        self.assertEqual(best_proposal.scheduler, 'BisectScheduler')
        self.git('merge-base', '--is-ancestor', self.preb1, best_proposal.commit)
        self.git('merge-base', '--is-ancestor', best_proposal.commit, self.postb2)
        precommits = self.scheduler.count_commits(self.preb1, best_proposal.commit)
        postcommits = self.scheduler.count_commits(best_proposal.commit, self.postb2)
        self.assertLessEqual(abs(precommits-postcommits),1)
        self.updater.set_scheduled(best_proposal.commit, 'box', datetime.timedelta(hours=4))
        best_proposal = self._get_best_proposal(self.scheduler, datetime.datetime.now(), 'commit [36]', 8, False)

class TestMergeScheduler(TestScheduler):
    def test_get_proposal(self):
        self.state.set_last_good(self.preb1)
        self.bisect_scheduler = tb3.scheduler.BisectScheduler('linux', 'master', self.testdir)
        self.head_scheduler = tb3.scheduler.HeadScheduler('linux', 'master', self.testdir)
        self.merge_scheduler = tb3.scheduler.MergeScheduler('linux', 'master', self.testdir)
        self.merge_scheduler.add_scheduler(self.bisect_scheduler)
        self.merge_scheduler.add_scheduler(self.head_scheduler)
        proposals = self.merge_scheduler.get_proposals(datetime.datetime.now())
        self.assertEqual(len(proposals), 9)
        self.assertEqual(set((p.scheduler for p in proposals)), set(['HeadScheduler']))
        proposal = proposals[0]
        self.assertEqual(proposal.commit, self.head)
        self.assertEqual(proposal.scheduler, 'HeadScheduler')
        self.state.set_first_bad(self.preb2)
        self.state.set_last_bad(self.postb1)
        proposals = self.merge_scheduler.get_proposals(datetime.datetime.now())
        self.assertEqual(len(proposals), 4)
        self.assertEqual(set((p.scheduler for p in proposals)), set(['HeadScheduler', 'BisectScheduler']))
        proposal = proposals[0]
        self.git('merge-base', '--is-ancestor', self.preb2, proposal.commit)
        self.assertEqual(proposal.scheduler, 'HeadScheduler')


if __name__ == '__main__':
    unittest.main()
# vim: set et sw=4 ts=4:
