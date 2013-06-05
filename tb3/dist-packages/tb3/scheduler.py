#!/usr/bin/env python
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

import sh
import math
import tb3.repostate
import functools
import datetime

class Proposal:
    def __init__(self, score, commit, scheduler):
        (self.score, self.commit, self.scheduler) = (score, commit, scheduler)
    def __repr__(self):
        return 'Proposal(%f, %s, %s)' % (self.score, self.commit, self.scheduler)
    def __cmp__(self, other):
        return other.score - self.score

class Scheduler:
    def __init__(self, platform, branch, repo):
        self.branch = branch
        self.repo = repo
        self.platform = platform
        self.repostate = tb3.repostate.RepoState(self.platform, self.branch, self.repo)
        self.repohistory = tb3.repostate.RepoHistory(self.platform, self.repo)
        self.git = sh.git.bake(_cwd=repo)
    def count_commits(self, start, to):
        return int(self.git('rev-list', '%s..%s' % (start, to), count=True))
    def get_commits(self, begin, end):
        commits = []
        for commit in self.git('rev-list', '%s..%s' % (begin, end)).strip('\n').split('\n'):
            if len(commit) == 40:
                commits.append( (len(commits), commit, self.repohistory.get_commit_state(commit)) )
        return commits
    def norm_results(self, proposals):
        maxscore = 0
        #maxscore = functools.reduce( lambda x,y: max(x.score, y.score), proposals)
        for proposal in proposals:
            maxscore = max(maxscore, proposal.score)
        if maxscore > 0:
            for proposal in proposals:
                proposal.score = proposal.score / maxscore * len(proposals)
    def dampen_running_commits(self, commits, proposals, time):
        for commit in commits:
            if commit[2].state == 'RUNNING':
                running_time = max(datetime.timedelta(), time - commit[2].started)
                timedistance = running_time.total_seconds() / commit[2].estimated_duration.total_seconds()
                for idx in range(len(proposals)):
                    proposals[idx].score *= 1-1/((commit[0]-idx+timedistance)**2+1)
    def get_proposals(self, time):
        return [(0, None, self.__class__.__name__)]

class HeadScheduler(Scheduler):
    def get_proposals(self, time):
        head = self.repostate.get_head()
        last_build = self.repostate.get_last_build()
        proposals = []
        if not last_build is None:
            commits = self.get_commits(last_build, head)
            for commit in commits:
                proposals.append(Proposal(1-1/((len(commits)-float(commit[0]))**2+1), commit[1], self.__class__.__name__))
            self.dampen_running_commits(commits, proposals, time)
        else:
            proposals.append(Proposal(float(1), head, self.__class__.__name__))
        self.norm_results(proposals)
        return proposals

class BisectScheduler(Scheduler):
    def __init__(self, platform, branch, repo):
        Scheduler.__init__(self, platform, branch, repo)
    def get_proposals(self, time):
        last_good = self.repostate.get_last_good()
        first_bad = self.repostate.get_first_bad()
        if last_good is None or first_bad is None:
            return []
        commits = self.get_commits(last_good, '%s^' % first_bad)
        proposals = []
        for commit in commits:
            proposals.append(Proposal(1.0, commit[1], self.__class__.__name__))
        for idx in range(len(proposals)):
            proposals[idx].score *= (1-1/(float(idx)**2+1)) * (1-1/((float(idx-len(proposals)))**2+1))
        self.dampen_running_commits(commits, proposals, time)
        self.norm_results(proposals)
        return proposals

class MergeScheduler(Scheduler):
    def __init__(self, platform, branch, repo):
        Scheduler.__init__(self, platform, branch, repo)
        self.schedulers = []
    def add_scheduler(self, scheduler, weight=1):
        self.schedulers.append((weight, scheduler))
    def get_proposals(self, time):
        proposals = []
        for scheduler in self.schedulers:
            new_proposals = scheduler[1].get_proposals(time)
            for proposal in new_proposals:
                proposal.score *= scheduler[0]
                proposals.append(proposal)
        return sorted(proposals)
# vim: set et sw=4 ts=4:
